// @ts-check

const common = [
	"bun tools/end-of-file.ts",
	"bun tools/trailing-whitespace.ts",
	"bun tools/codespell.ts",
];

/**
 * @type {import('lint-staged').Configuration}
 */
export default {
	"*": common,
	"*.{mjs,js,json,ts,tsx}": [
		...common,
		"biome check --write --unsafe --no-errors-on-unmatched",
		"biome format --write --no-errors-on-unmatched",
		"biome lint --write --no-errors-on-unmatched",
	],
	"*.zig": [...common, "zlint --verbose", "zig fmt"],
	"*.zx": [
		...common,
		// "zig build zx -- fmt",
	],
};
