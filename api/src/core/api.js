import cors from "cors";
import http from "node:http";
import rateLimit from "express-rate-limit";
import { setGlobalDispatcher, ProxyAgent } from "undici";
import {
  getCommit,
  getBranch,
  getRemote,
  getVersion,
} from "@imput/version-info";

import jwt from "../security/jwt.js";
import stream from "../stream/stream.js";
import match from "../processing/match.js";

import { env, isCluster, setTunnelPort } from "../config.js";
import { extract } from "../processing/url.js";
import { Green, Bright, Cyan, Red } from "../misc/console-text.js";
import { hashHmac } from "../security/secrets.js";
import { createStore } from "../store/redis-ratelimit.js";
import { randomizeCiphers } from "../misc/randomize-ciphers.js";
import { verifyTurnstileToken } from "../security/turnstile.js";
import { friendlyServiceName } from "../processing/service-alias.js";
import { verifyStream, getInternalStream } from "../stream/manage.js";
import {
  createResponse,
  normalizeRequest,
  getIP,
} from "../processing/request.js";

import * as APIKeys from "../security/api-keys.js";
import * as Cookies from "../processing/cookie/manager.js";
import * as YouTubeSession from "../processing/helpers/youtube-session.js";

let gitInfo = {
  branch: process.env.GIT_BRANCH_NAME || "unknown",
  commit: process.env.GIT_COMMIT_SHA_SHORT || "unknown",
  remote: process.env.GIT_REMOTE_URL || "unknown",
};
let versionInfo = process.env.APP_VERSION || "unknown";

try {
  const liveBranch = await getBranch();
  const liveCommit = await getCommit();
  const liveRemote = await getRemote();
  const liveVersion = await getVersion();

  gitInfo = {
    branch: liveBranch || gitInfo.branch,
    commit: liveCommit || gitInfo.commit,
    remote: liveRemote || gitInfo.remote,
  };
  versionInfo = liveVersion || versionInfo;
} catch (error) {
  console.warn(
    Red(
      "[WARN] Failed to dynamically get Git/version information. Using fallbacks/environment variables. Error: " +
        error.message
    )
  );
}

const acceptRegex = /^application\/json(; charset=utf-8)?$/;

const corsConfig = env.corsWildcard
  ? {}
  : {
      origin: env.corsURL,
      optionsSuccessStatus: 200,
    };

const fail = (res, code, context) => {
  const { status, body } = createResponse("error", { code, context });
  res.status(status).json(body);
};

export const runAPI = async (express, app, __dirname, isPrimary = true) => {
  const startTime = new Date();
  const startTimestamp = startTime.getTime();

  const serverInfo = JSON.stringify({
    cobalt: {
      version: versionInfo,
      url: env.apiURL,
      startTime: `${startTimestamp}`,
      durationLimit: env.durationLimit,
      turnstileSitekey: env.sessionEnabled ? env.turnstileSitekey : undefined,
      services: [...env.enabledServices].map((e) => {
        return friendlyServiceName(e);
      }),
    },
    git: gitInfo,
  });

  const handleRateExceeded = (_, res) => {
    const { status, body } = createResponse("error", {
      code: "error.api.rate_exceeded",
      context: {
        limit: env.rateLimitWindow,
      },
    });
    return res.status(status).json(body);
  };

  const keyGenerator = (req) =>
    hashHmac(getIP(req), "rate").toString("base64url");

  const sessionLimiter = rateLimit({
    windowMs: env.sessionRateLimitWindow * 1000,
    limit: env.sessionRateLimit,
    standardHeaders: "draft-6",
    legacyHeaders: false,
    keyGenerator,
    store: await createStore("session"),
    handler: handleRateExceeded,
  });

  const apiLimiter = rateLimit({
    windowMs: env.rateLimitWindow * 1000,
    limit: (req) => req.rateLimitMax || env.rateLimitMax,
    standardHeaders: "draft-6",
    legacyHeaders: false,
    keyGenerator: (req) => req.rateLimitKey || keyGenerator(req),
    store: await createStore("api"),
    handler: handleRateExceeded,
  });

  const apiTunnelLimiter = rateLimit({
    windowMs: env.rateLimitWindow * 1000,
    limit: (req) => req.rateLimitMax || env.rateLimitMax,
    standardHeaders: "draft-6",
    legacyHeaders: false,
    keyGenerator: (req) => req.rateLimitKey || keyGenerator(req),
    store: await createStore("tunnel"),
    handler: (_, res) => {
      return res.sendStatus(429);
    },
  });

  app.set("trust proxy", ["loopback", "uniquelocal"]);

  app.use(
    "/",
    cors({
      methods: ["GET", "POST"],
      exposedHeaders: [
        "Ratelimit-Limit",
        "Ratelimit-Policy",
        "Ratelimit-Remaining",
        "Ratelimit-Reset",
      ],
      ...corsConfig,
    })
  );

  app.post("/", (req, res, next) => {
    if (!acceptRegex.test(req.header("Accept"))) {
      return fail(res, "error.api.header.accept");
    }
    if (!acceptRegex.test(req.header("Content-Type"))) {
      return fail(res, "error.api.header.content_type");
    }
    next();
  });

  app.post("/", (req, res, next) => {
    if (!env.apiKeyURL) {
      return next();
    }

    const { success, error } = APIKeys.validateAuthorization(req);
    if (!success) {
      if (
        (env.sessionEnabled || !env.authRequired) &&
        ["missing", "not_api_key"].includes(error)
      ) {
        return next();
      }
      return fail(res, `error.api.auth.key.${error}`);
    }
    return next();
  });

  app.post("/", (req, res, next) => {
    if (!env.sessionEnabled || req.rateLimitKey) {
      return next();
    }

    try {
      const authorization = req.header("Authorization");
      if (!authorization) {
        return fail(res, "error.api.auth.jwt.missing");
      }

      if (authorization.length >= 256) {
        return fail(res, "error.api.auth.jwt.invalid");
      }

      const [type, token, ...rest] = authorization.split(" ");
      if (!token || type.toLowerCase() !== "bearer" || rest.length) {
        return fail(res, "error.api.auth.jwt.invalid");
      }

      if (!jwt.verify(token, getIP(req, 32))) {
        return fail(res, "error.api.auth.jwt.invalid");
      }

      req.rateLimitKey = hashHmac(token, "rate");
    } catch {
      return fail(res, "error.api.generic");
    }
    next();
  });

  app.post("/", apiLimiter);
  app.use("/", express.json({ limit: 1024 }));

  app.use("/", (err, _, res, next) => {
    if (err) {
      const { status, body } = createResponse("error", {
        code: "error.api.invalid_body",
      });
      return res.status(status).json(body);
    }
    next();
  });

  app.post("/session", sessionLimiter, async (req, res) => {
    if (!env.sessionEnabled) {
      return fail(res, "error.api.auth.not_configured");
    }

    const turnstileResponse = req.header("cf-turnstile-response");

    if (!turnstileResponse) {
      return fail(res, "error.api.auth.turnstile.missing");
    }

    const turnstileResult = await verifyTurnstileToken(
      turnstileResponse,
      req.ip
    );

    if (!turnstileResult) {
      return fail(res, "error.api.auth.turnstile.invalid");
    }

    try {
      res.json(jwt.generate(getIP(req, 32)));
    } catch {
      return fail(res, "error.api.generic");
    }
  });

  app.post("/", async (req, res) => {
    const request = req.body;

    if (!request.url) {
      return fail(res, "error.api.link.missing");
    }

    const { success, data: normalizedRequest } = await normalizeRequest(
      request
    );
    if (!success) {
      return fail(res, "error.api.invalid_body");
    }

    const parsed = extract(normalizedRequest.url);

    if (!parsed) {
      return fail(res, "error.api.link.invalid");
    }
    if ("error" in parsed) {
      let context;
      if (parsed?.context) {
        context = parsed.context;
      }
      return fail(res, `error.api.${parsed.error}`, context);
    }

    try {
      const result = await match({
        host: parsed.host,
        patternMatch: parsed.patternMatch,
        params: normalizedRequest,
      });

      res.status(result.status).json(result.body);
    } catch {
      fail(res, "error.api.generic");
    }
  });

  app.get("/tunnel", apiTunnelLimiter, async (req, res) => {
    const id = String(req.query.id);
    const exp = String(req.query.exp);
    const sig = String(req.query.sig);
    const sec = String(req.query.sec);
    const iv = String(req.query.iv);

    const checkQueries = id && exp && sig && sec && iv;
    const checkBaseLength = id.length === 21 && exp.length === 13;
    const checkSafeLength =
      sig.length === 43 && sec.length === 43 && iv.length === 22;

    if (!checkQueries || !checkBaseLength || !checkSafeLength) {
      return res.status(400).end();
    }

    if (req.query.p) {
      return res.status(200).end();
    }

    const streamInfo = await verifyStream(id, sig, exp, sec, iv);
    if (!streamInfo?.service) {
      return res.status(streamInfo.status).end();
    }

    if (streamInfo.type === "proxy") {
      streamInfo.range = req.headers["range"];
    }

    return stream(res, streamInfo);
  });

  const itunnelHandler = (req, res) => {
    if (!req.ip.endsWith("127.0.0.1")) {
      return res.sendStatus(403);
    }

    if (String(req.query.id).length !== 21) {
      return res.sendStatus(400);
    }

    const streamInfo = getInternalStream(req.query.id);
    if (!streamInfo) {
      return res.sendStatus(404);
    }

    streamInfo.headers = new Map([
      ...(streamInfo.headers || []),
      ...Object.entries(req.headers),
    ]);

    return stream(res, { type: "internal", data: streamInfo });
  };

  app.get("/itunnel", itunnelHandler);

  app.get("/", (_, res) => {
    res.type("json");
    res.status(200).send(serverInfo);
  });

  app.get("/favicon.ico", (req, res) => {
    res.status(404).end();
  });

  app.get("/*", (req, res) => {
    res.redirect("/");
  });

  app.use((_, __, res, ___) => {
    return fail(res, "error.api.generic");
  });

  randomizeCiphers();
  setInterval(randomizeCiphers, 1000 * 60 * 30);

  if (env.externalProxy) {
    if (env.freebindCIDR) {
      throw new Error(
        "Freebind is not available when external proxy is enabled"
      );
    }
    setGlobalDispatcher(new ProxyAgent(env.externalProxy));
  }

  http.createServer(app).listen(
    {
      port: env.apiPort,
      host: env.listenAddress,
      reusePort: env.instanceCount > 1 || undefined,
    },
    () => {
      if (isPrimary) {
        console.log(
          `\n` +
            Bright(Cyan("cobalt ")) +
            Bright("API ^ω^") +
            "\n" +
            "~~~~~~\n" +
            Bright("version: ") +
            versionInfo +
            "\n" +
            Bright("commit: ") +
            gitInfo.commit +
            "\n" +
            Bright("branch: ") +
            gitInfo.branch +
            "\n" +
            Bright("remote: ") +
            gitInfo.remote +
            "\n" +
            Bright("start time: ") +
            startTime.toUTCString() +
            "\n" +
            "~~~~~~\n" +
            Bright("url: ") +
            Bright(Cyan(env.apiURL)) +
            "\n" +
            Bright("port: ") +
            env.apiPort +
            "\n"
        );
      }

      if (env.apiKeyURL) {
        APIKeys.setup(env.apiKeyURL);
      }

      if (env.cookiePath) {
        Cookies.setup(env.cookiePath);
      }

      if (env.ytSessionServer) {
        YouTubeSession.setup();
      }
    }
  );

  if (isCluster) {
    const istreamer = express();
    istreamer.get("/itunnel", itunnelHandler);
    const server = istreamer.listen(
      {
        port: 0,
        host: "127.0.0.1",
        exclusive: true,
      },
      () => {
        const { port } = server.address();
        console.log(
          `${Green("[✓]")} cobalt sub-instance running on 127.0.0.1:${port}`
        );
        setTunnelPort(port);
      }
    );
  }
};
