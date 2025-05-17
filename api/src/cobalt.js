import "dotenv/config";

import express from "express";
import cluster from "node:cluster";

import path from "path";
import { fileURLToPath } from "url";

import { env, isCluster } from "./config.js";
import { Red, Green } from "./misc/console-text.js";
import { initCluster } from "./misc/cluster.js";

const app = express();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename).slice(0, -4);

app.disable("x-powered-by");

if (env.apiURL) {
  console.log(Green("Attempting to import and run API..."));
  const { runAPI } = await import("./core/api.js");

  if (isCluster) {
    console.log(Green("Initializing cluster..."));
    await initCluster();
    console.log(Green("Cluster initialized."));
  }

  console.log(Green("Calling runAPI..."));
  runAPI(express, app, __dirname, cluster.isPrimary);
  console.log(
    Green(
      "runAPI call has been made in src/cobalt.js. Waiting for server to listen or script to end."
    )
  );
} else {
  console.log(Red("API_URL env variable is missing, cobalt api can't start."));
}
