/**
 * @filename: lint-staged.config.js
 * @type {import('lint-staged').Configuration}
 */
export default {
	"*.{mjs,js,json,ts,tsx}": [
		"biome check --write",
		"biome check --write --unsafe",
		"biome format --write --no-errors-on-unmatched",
		"biome lint --write --no-errors-on-unmatched",
	],
	"*.zig": ["zlint --verbose", "zig fmt"],
	// "*.zx": "zig build zx -- fmt", // TODO: enable when formatter improves
};
