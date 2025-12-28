/**
 * @filename: lint-staged.config.js
 * @type {import('lint-staged').Configuration}
 */

const common = [
	"bun tools/end-of-file.ts",
	"bun tools/trailing-whitespace.ts",
	"bun tools/codespell.ts",
];

export default {
	"*": common,
	"*.{mjs,js,json,ts,tsx}": [
		...common,
		"biome check --write --unsafe --no-errors-on-unmatched",
		"biome format --write --no-errors-on-unmatched",
		"biome lint --write --no-errors-on-unmatched",
	],
	"*.zig": [
		...common,
		"zlint --verbose",
		"zig fmt",
		// this makes the test run once, rather than once per file
		() => "zig build test",
	],
	"*.zx": [
		...common,
		"bun tools/codespell.ts",
		// "zig build zx -- fmt",
	],
};
