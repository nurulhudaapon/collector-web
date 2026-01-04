import { afterAll, beforeAll, expect, it } from "bun:test";

import { type ChildProcessByStdio, execSync, spawn } from "node:child_process";
import type { Readable } from "node:stream";

type Json = Record<string, string | number>;
type Request = Json;
type Response = {
	code: number;
	json: Json;
};

const baseUrl = "http://localhost:3000";

let server: ChildProcessByStdio<null, null, Readable> | null = null;

beforeAll(
	async () => {
		// NOTE: non-0 output throws
		execSync("zig build", { stdio: "ignore" });

		// FIXME: `zig build run` doesn't quite work (server isn't closed)
		// perhaps it doesn't properly stop exe's thread when it itself is killed
		server = spawn("zig-out/bin/collector-web", {
			stdio: ["ignore", "ignore", "pipe"],
			// with __TESTING__ set, in-memory database is used
			env: { ...process.env, __TESTING__: "" },
		});

		if (server.stderr !== null) {
			server.stderr.on("data", (chunk: object) => {
				// console.log already adds newline, avoid writing empty lines
				const withoutNewLine: string = chunk.toString().trimEnd();

				// strip "zx - vXXX | http:..." line from output
				if (!withoutNewLine.includes(`| ${baseUrl}`)) {
					console.log(`[SERVER]: ${withoutNewLine}`);
				}
			});
		}
	},
	// long timeout = we can `zig build` without error
	{ timeout: 30_000 },
);

afterAll(async () => {
	if (server !== null) {
		server.kill("SIGINT");
	}
});

const callApi = async <T extends Request>(
	path: string,
	Request: T,
): Promise<Response> => {
	const response = await fetch(baseUrl + path, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(Request),
	});

	const text = await response.text();

	const clean = text.replace("<!DOCTYPE html>", "");
	if (clean.length === 0) {
		throw new Error("empty response");
	}

	return {
		code: response.status,
		json: JSON.parse(clean),
	};
};

const expectSuccess = (response: Response) => {
	expect(response.code, response.json.error).toBe(200);
	expect(response.json).not.toHaveProperty("error");
};

const expectError = (response: Response) => {
	expect(response.code, response.json).toBe(500);
	expect(response.json).toHaveProperty("error");
};

it("should error logging out without being logged in", async () => {
	const status = await callApi("/api/logout", {
		token: 1234,
	});
	expectError(status);
});

it("should create an account and log with it", async () => {
	const payload = {
		username: "user",
		password: "secret",
		referrer: "/",
	};

	const signin = await callApi("/api/signin", payload);
	expectSuccess(signin);
	expect(signin.json).toHaveProperty("token");
	expect(signin.json.token).toBeTypeOf("string");

	const login = await callApi("/api/login", payload);
	expectSuccess(login);
	expect(login.json).toHaveProperty("token");
	expect(login.json.token).toBeTypeOf("string");
});

it("should error fetching status of invalid ID", async () => {
	const status = await callApi("/api/fetch/status", {
		id: 1234,
	});
	expectError(status);
});

it("should start a fetch task and query its status", async () => {
	const start = await callApi("/api/fetch/start", {
		name: "pikachu",
	});
	expectSuccess(start);
	expect(start.json).toHaveProperty("id");
	expect(start.json.id).toBeTypeOf("number");

	const status = await callApi("/api/fetch/status", {
		id: start.json.id as number,
	});
	expectSuccess(status);
	expect(status.json).toHaveProperty("count");
	expect(status.json).toHaveProperty("finished");
	expect(status.json.finished).toBe(false);
	expect(status.json).toHaveProperty("ms_elapsed");
});
