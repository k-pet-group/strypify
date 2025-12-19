const { contextBridge } = require('electron');
const {readFileSync} = require("node:fs");

contextBridge.exposeInMainWorld('electron', {
        setFile: async (selector, filePath) => {
                const input = document.querySelector(selector);
                if (!input) {
                        throw new Error('Input not found: ' + selector);
                }

                const buffer = readFileSync(filePath);
                const blob = new Blob([buffer]);
                const file = new File([blob], require('path').basename(filePath));
                const dt = new DataTransfer();
                dt.items.add(file);

                input.files = dt.files;
                input.dispatchEvent(new Event('input', { bubbles: true }));
                input.dispatchEvent(new Event('change', { bubbles: true }));

                return true; // success signal
        }
});
