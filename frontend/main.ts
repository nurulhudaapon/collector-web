import { init, jsz } from "ziex/wasm";

const importObject: WebAssembly.Imports = {
	"collector-web": {
		awaitPromise: (promiseId: number): void => {
			const exports = wasm?.instance.exports;
			if (!exports) return;

			const promiseCompleted = exports.promiseCompleted as (
				success: boolean,
				value: object,
			) => void;

			const promise: Promise<object> = jsz.loadValue(promiseId);

			promise
				.then((value) => promiseCompleted(true, value))
				.catch((reason) => promiseCompleted(false, reason));
		},
	},
};

let wasm: WebAssembly.WebAssemblyInstantiatedSource | null = null;

init({
	importObject,
}).then((value) => {
	wasm = value;
});
