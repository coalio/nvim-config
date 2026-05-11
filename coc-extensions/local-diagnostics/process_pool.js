"use strict";

const childProcess = require("node:child_process");

class ProcessPool {
  constructor(log) {
    this.log = log;
    this.running = new Map();
    this.nextRunId = 0;
  }

  cancel(adapter) {
    const running = this.running.get(adapter);
    if (!running || !running.child || running.child.killed) {
      return;
    }

    try {
      running.child.kill();
    } catch (_error) {
    }
  }

  run(adapter, command, args, options = {}) {
    this.cancel(adapter);
    const runId = ++this.nextRunId;

    return new Promise((resolve) => {
      const child = childProcess.spawn(command, args, {
        cwd: options.cwd,
        env: process.env,
        windowsHide: true,
      });
      this.running.set(adapter, { child, runId });

      let stdout = "";
      let stderr = "";

      child.stdout.on("data", (chunk) => {
        stdout += chunk.toString();
      });
      child.stderr.on("data", (chunk) => {
        stderr += chunk.toString();
      });
      child.on("error", (error) => {
        resolve({ error, stdout, stderr, code: null, signal: null, stale: this.isStale(adapter, runId) });
      });
      child.on("close", (code, signal) => {
        const stale = this.isStale(adapter, runId);
        if (!stale) {
          this.running.delete(adapter);
        }
        resolve({ stdout, stderr, code, signal, stale });
      });
    });
  }

  isStale(adapter, runId) {
    const running = this.running.get(adapter);
    return Boolean(running && running.runId !== runId);
  }

  dispose() {
    for (const adapter of this.running.keys()) {
      this.cancel(adapter);
    }
    this.running.clear();
  }
}

module.exports = {
  ProcessPool,
};
