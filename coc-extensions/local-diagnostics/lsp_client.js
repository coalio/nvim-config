"use strict";

const childProcess = require("node:child_process");

class LspClient {
  constructor(command, args, options = {}) {
    this.command = command;
    this.args = args;
    this.cwd = options.cwd;
    this.env = options.env || process.env;
    this.log = options.log || (() => {});
    this.onNotification = options.onNotification || (() => {});
    this.onRequest = options.onRequest || (() => undefined);
    this.nextId = 1;
    this.pending = new Map();
    this.buffer = Buffer.alloc(0);
    this.disposed = false;
    this.child = childProcess.spawn(command, args, {
      cwd: this.cwd,
      env: this.env,
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
    });

    this.child.stdout.on("data", (chunk) => this.read(chunk));
    this.child.stderr.on("data", (chunk) => {
      const message = chunk.toString().trim();
      if (message) {
        this.log(message);
      }
    });
    this.child.on("error", (error) => {
      this.rejectAll(error);
    });
    this.child.on("close", (code, signal) => {
      this.rejectAll(new Error(`language server exited with code ${code} signal ${signal}`));
    });
  }

  send(payload) {
    if (this.disposed || !this.child || !this.child.stdin.writable) {
      return;
    }

    const body = JSON.stringify(payload);
    this.child.stdin.write(`Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`);
  }

  notify(method, params) {
    this.send({ jsonrpc: "2.0", method, params });
  }

  request(method, params, timeoutMs = 15000) {
    const id = this.nextId++;
    this.send({ jsonrpc: "2.0", id, method, params });

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`request timed out: ${method}`));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });
    });
  }

  read(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);

    while (true) {
      const headerEnd = this.buffer.indexOf("\r\n\r\n");
      if (headerEnd < 0) {
        return;
      }

      const header = this.buffer.slice(0, headerEnd).toString("ascii");
      const match = /Content-Length:\s*(\d+)/i.exec(header);
      if (!match) {
        this.dispose();
        this.rejectAll(new Error(`invalid LSP header: ${header}`));
        return;
      }

      const contentLength = Number(match[1]);
      const bodyStart = headerEnd + 4;
      const bodyEnd = bodyStart + contentLength;
      if (this.buffer.length < bodyEnd) {
        return;
      }

      const body = this.buffer.slice(bodyStart, bodyEnd).toString("utf8");
      this.buffer = this.buffer.slice(bodyEnd);

      try {
        this.handle(JSON.parse(body));
      } catch (error) {
        this.log(`could not parse LSP message: ${error.message || String(error)}`);
      }
    }
  }

  handle(message) {
    if (message.id !== undefined && this.pending.has(message.id)) {
      const pending = this.pending.get(message.id);
      this.pending.delete(message.id);
      clearTimeout(pending.timer);
      if (message.error) {
        pending.reject(new Error(message.error.message || JSON.stringify(message.error)));
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    if (message.id !== undefined && message.method) {
      Promise.resolve(this.onRequest(message.method, message.params))
        .then((result) => {
          this.send({ jsonrpc: "2.0", id: message.id, result: result === undefined ? null : result });
        })
        .catch((error) => {
          this.send({
            jsonrpc: "2.0",
            id: message.id,
            error: { code: -32603, message: error.message || String(error) },
          });
        });
      return;
    }

    if (message.method) {
      this.onNotification(message.method, message.params);
    }
  }

  async shutdown(timeoutMs = 2000) {
    if (this.disposed) {
      return;
    }

    try {
      await this.request("shutdown", null, timeoutMs);
      this.notify("exit");
    } catch (_error) {
    } finally {
      this.dispose();
    }
  }

  rejectAll(error) {
    for (const [id, pending] of this.pending.entries()) {
      clearTimeout(pending.timer);
      pending.reject(error);
      this.pending.delete(id);
    }
  }

  dispose() {
    if (this.disposed) {
      return;
    }

    this.disposed = true;
    this.rejectAll(new Error("language server disposed"));

    if (this.child && !this.child.killed) {
      try {
        this.child.kill();
      } catch (_error) {
      }
    }
  }
}

module.exports = {
  LspClient,
};
