const { app, BrowserWindow, clipboard} = require('electron')
const {writeFileSync, writeSync, readFileSync, existsSync, rmSync, mkdtempSync} = require("node:fs");
const crypto = require('crypto');
const sharp = require('sharp');
const path = require('path');

// Print version and exit, if they asked for it:
if (process.argv.includes("--version") || process.argv.includes("-v")) {
    console.log(app.getVersion());
    app.exit(0);
}

// Gets the union of the two rectangles, i.e. the smallest rectangle
// that includes the full bounds of both the given rectangles.
function getUnion(rect1, rect2) {
    // Determine the minimum x and y values
    const minX = Math.min(rect1.x, rect2.x);
    const minY = Math.min(rect1.y, rect2.y);

    // Determine the maximum x and y values
    const maxX = Math.max(rect1.x + rect1.width, rect2.x + rect2.width);
    const maxY = Math.max(rect1.y + rect1.height, rect2.y + rect2.height);

    // Calculate the union rectangle
    const unionRect = {
        x: minX,
        y: minY,
        width: maxX - minX,
        height: maxY - minY
    };

    return unionRect;
}

function integerRect(rect) {
    const x1 = Math.floor(rect.x);
    const y1 = Math.floor(rect.y);
    const x2 = Math.ceil(rect.x + rect.width);
    const y2 = Math.ceil(rect.y + rect.height);

    return {
        x: x1,
        y: y1,
        width: x2 - x1,
        height: y2 - y1
    };
}

async function captureRect(win, rect, zoom, outputFile) {
    const wc = win.webContents;

    // The rect coordinates are in device pixels.

    // Get viewport size, minus a little tolerance:
    let { innerWidth: viewportWidth, innerHeight: viewportHeight } =
        await wc.executeJavaScript(`({ innerWidth: Math.ceil(window.innerWidth - 5), innerHeight: Math.ceil(window.innerHeight - 5)})`);

    // We convert the viewport from CSS pixels into device pixels:
    viewportWidth = viewportWidth * zoom;
    viewportHeight = viewportHeight * zoom;

    const chunks = [];

    // Divide rectangle into vertical chunks
    const captureWidth = Math.floor(Math.min(viewportWidth, rect.width));
    for (let offsetY = 0; offsetY < rect.height; offsetY += Math.floor(viewportHeight)) {
        // targetScrollY is device pixels:
        const targetScrollY = rect.y + offsetY;
        const captureHeight = Math.floor(Math.min(viewportHeight, rect.height - offsetY));

        //console.log("Capturing chunk Y: " + targetScrollY + "+" + captureHeight, " with X: " + rect.x + "+" + rect.width + " and viewportSize: " + viewportWidth + " x " + viewportHeight);

        // Scroll to the vertical position (converting back into CSS Pixels)
        await wc.executeJavaScript(`document.getElementById("editorCodeDiv").scrollTo(0, ${targetScrollY / zoom})`);
        await new Promise(resolve => setTimeout(resolve, 200)); // allow rendering

        const actualScrollY = await wc.executeJavaScript("document.getElementById('editorCodeDiv').scrollTop") * zoom;

        //console.log("Target scroll: " + targetScrollY + " actual: " + actualScrollY);

        // Capture visible viewport
        const image = await wc.capturePage({
            x: rect.x,
            // Adjust if we didn't scroll as far down as we wanted:
            y: 0 + (targetScrollY - actualScrollY),
            width: captureWidth,
            height: captureHeight
        });

        //console.log("Chunk size: " + captureWidth + " x " + captureHeight + " @ " + offsetY);

        let buffer = image.toPNG();
        // Cancel any Mac High-DPI:
        buffer = await sharp(buffer)
            .resize(captureWidth, captureHeight, { fit: 'fill' })
            .toBuffer();
        chunks.push({ buffer: buffer, offsetY });
    }

    // Stitch chunks vertically
    let composite = sharp({
        create: {
            width: captureWidth,
            height: rect.height,
            channels: 4,
            background: { r: 255, g: 255, b: 255, alpha: 0 }
        }
    });

    //console.log("Composite size: " + captureWidth + " x " + rect.height);
    //const [baseMeta, chunkMeta] = await Promise.all([
    //    composite.metadata(),
    //    sharp(chunks[0].buffer).metadata()
    //]);
    //console.log(baseMeta.width, baseMeta.height, chunkMeta.width, chunkMeta.height);


    await composite.composite(
        chunks.map(chunk => ({ input: chunk.buffer, top: chunk.offsetY, left: 0 }))
    ).toFile(outputFile);
}


let zoom = parseFloat(app.commandLine.getSwitchValue("zoom"));
if (!zoom || isNaN(zoom)) {
    zoom = 2.5;
}

let editorURL = app.commandLine.getSwitchValue("editor-url") || "https://strype.org/editor/";
if (!(editorURL.startsWith("https:") || editorURL.startsWith("http:"))) {
    if (editorURL.startsWith("localhost")) {
        editorURL = "http://" + editorURL;
    }
    else {
        editorURL = "https://" + editorURL;
    }
}

let arg = app.commandLine.getSwitchValue("file");
if (!arg) {
    console.log("Must pass Python code as argument, e.g. --file=myfile.py (the equals is required)");
    app.exit(-1);
}
let completeSource;
if (existsSync(arg)) {
    completeSource = readFileSync(arg).toString();
} else {
    console.log("Cannot find file " + arg);
    app.exit(-1);
}

let destFilename = app.commandLine.getSwitchValue("output-file");
if (!destFilename) {
    // Default filename is predetermined by the MD5 hash of the code.  This helps with caching the image to avoid
    // unnecessary regeneration.
    destFilename = 'strype-' + crypto.createHash('md5').update(completeSource).digest('hex') + '.png';
    if (existsSync(destFilename)) {
        try {
            writeSync(3, destFilename);
        } catch (err) {
        }
        app.exit(0);
    }
}
// Note: if they specified filename we always overwrite

const cursorNavigation = app.commandLine.getSwitchValue("cursor-navigation");
let navigationCommands = null;
if (cursorNavigation) {
    // Remove all spaces and split by commas:
    const items = cursorNavigation.toLowerCase().replace(/\s+/g, "").split(",");

    // mapping table
    const map = {
        up: "Up",
        down: "Down",
        left: "Left",
        right: "Right",
        home: "Home",
        end: "End"
    };

    const result = [];

    for (let item of items) {
        if (!item) continue;

        let count = 1;
        let action = item;

        // 3. handle N*action or action*N
        let match = item.match(/^(\d+)\*(\w+)$/);
        if (match) {
            count = Number(match[1]);
            action = match[2];
        }
        else {
            match = item.match(/^(\w+)\*(\d+)$/);
            if (match) {
                count = Number(match[2]);
                action = match[1];
            }
        }

        // 4. map up to ArrowUp etc.
        const mapped = map[action.toLowerCase()];
        if (!mapped) throw new Error("Unknown action: " + action);

        // 5. expand repetitions
        for (let i = 0; i < count; i++) {
            result.push(mapped);
        }
    }
    navigationCommands = result;
}

// Trim leading and trailing blank lines:
const allLines = completeSource.trim().split(/\r?\n/);

app.on('ready', async () => {
    const debugging = false;
    const testWin = new BrowserWindow({
        width: 1920,
        height: 1080 * 3,
        // Don't actually show the GUI (can toggle for debugging):
        show: debugging,
        webPreferences: {
            // Must turn off sandbox to be able to write image files:
            sandbox: false,
            // Also need to toggle for debugging:
            offscreen: !debugging,
            // Support for loading a file:
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,   // recommended
            nodeIntegration: false    // recommended
        },
    });


    const tempDir = mkdtempSync('strypify-');
    process.on('exit', () => {
        rmSync(tempDir, { recursive: true, force: true });
    });

    const tempFile = path.join(tempDir, 'strypify.spy');
    writeFileSync(tempFile, allLines.join("\n"));

    // Must get rid of old data to revert to basic project:
    await testWin.webContents.session.clearCache(function(){});
    await testWin.webContents.session.clearStorageData();

    async function sendKey(entry, delay)
    {
        testWin.webContents.sendInputEvent({...entry, type: "keyDown"});
        await new Promise(resolve => setTimeout(resolve, 25));
        testWin.webContents.sendInputEvent({...entry, type: "keyUp"});
        // Delay after:
        await new Promise(resolve => setTimeout(resolve, delay));
    }

    async function waitForSavedLabel(timeoutMs = 10000, intervalMs = 200) {
        const start = Date.now();

        while (Date.now() - start < timeoutMs) {
            const found = await testWin.webContents.executeJavaScript(`
              (() => {
                const el = document.querySelector('span.gdrive-sync-label');
                return el && el.textContent.trim() === 'Saved';
              })()
            `);

            if (found) return true; // found the element with "Saved"

            await new Promise((resolve) => setTimeout(resolve, intervalMs));
        }
        return false; // timeout
    }

    async function hasFrameDivs(frameContainer) {
        return await testWin.webContents.executeJavaScript(`
            (() => {
              const container = document.getElementById('${frameContainer}');
              if (!container) return false;
              return container.querySelector('.frame-div') !== null;
            })()
            `);
    }



    await testWin.loadURL(editorURL);
    testWin.webContents.on('did-stop-loading', async() => {
        // Set CSS:
        if (navigationCommands == null) {
            // Hide frame cursor:
            testWin.webContents.insertCSS(`
                .caret {
                  height: 0px !important;
                }
              `);
        }
        // Hide the DEVELOPMENT overlay if pointing to a Github instance:
        testWin.webContents.insertCSS(`
            body::before {
                content: "" !important;
            }        
        `);

        // Inject helper function for use in getting bounds:
        await testWin.webContents.executeJavaScript(`
            window.getUnionBoundsAsSemiStr = (selector, heightAdj) => {
                const elements = document.querySelectorAll(selector);
                if (elements.length === 0) return "";
    
                const firstRect = elements[0].getBoundingClientRect();
                let union = {
                    top: firstRect.top,
                    left: firstRect.left,
                    right: firstRect.right,
                    bottom: firstRect.bottom + heightAdj
                };
    
                elements.forEach(el => {
                    const rect = el.getBoundingClientRect();
                    union.top = Math.min(union.top, rect.top);
                    union.left = Math.min(union.left, rect.left);
                    union.right = Math.max(union.right, rect.right);
                    union.bottom = Math.max(union.bottom, rect.bottom + heightAdj);
                });
    
                union.width = union.right - union.left;
                union.height = union.bottom - union.top;
    
                return \`\${union.left};\${union.top};\${union.width};\${union.height}\`;
            };
            undefined; // Don't return anything (without this, tries to return function)
        `);

        testWin.webContents.setZoomFactor(zoom);

        // Tell it we are Playwright to allow using the <input> file selection:
        await testWin.webContents.executeJavaScript(`window.Playwright = true;`);

        // Show menu and click load project:
        await testWin.webContents.executeJavaScript(`
          document.getElementById('showHideMenu')?.click();
        `);
        await new Promise(resolve => setTimeout(resolve, 500));
        await testWin.webContents.executeJavaScript(`
          document.getElementById('loadProjectLink')?.click();
        `);
        await new Promise(resolve => setTimeout(resolve, 200));
        await testWin.webContents.executeJavaScript(`
          document.getElementById('loadFromFSStrypeButton')?.click();
        `);

        // Uses handler in preload.js:
        try {
            await testWin.webContents.executeJavaScript(`window.electron.setFile(${JSON.stringify('#importFileInput')}, ${JSON.stringify(tempFile)})`);
        } catch (err) {
            console.error('Failed to set file:', err);
        }

        // Wait until Saved indicator shows:
        const saved = await waitForSavedLabel();
        if (!saved) {
            console.log('Timed out waiting for project load');
            app.exit(-1);
        }

        if (navigationCommands != null) {
            for (let key of navigationCommands) {
                sendKey({keyCode: key}, 150);
            }
        }

        const hasImports = await hasFrameDivs('frameContainer_-1');
        const hasDefs = await hasFrameDivs('frameContainer_-2');
        const hasMain = await hasFrameDivs('frameContainer_-3');

        // Need to wait for re-render after navigating:
        await new Promise(resolve => setTimeout(resolve, 200));
        // Scroll to top of page:
        await testWin.webContents.executeJavaScript(`document.getElementById("editorCodeDiv").scrollTo(0, 0)`);
        await new Promise(resolve => setTimeout(resolve, 200)); // allow rendering
        // Could probably do this simpler, but had problems initially getting more complex objects
        // back from executeJavaScript, so we do it one primitive number at a time:
        const allBounds = await Promise.all([
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-1', 10)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-2', 10)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-3', -190)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-1 > .container-frames', 0)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-2 > .container-frames', 0)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-3 > .container-frames', 0)"),
                ]);
        function readBounds(i) {
            const bs = allBounds[i].split(";");
            return {x: zoom * bs[0], y: zoom * bs[1], width: zoom * bs[2], height: zoom * bs[3]};
        }
        //console.log("Bounds: " + JSON.stringify(allBounds));
        const importWholeBounds = readBounds(0);
        const defsWholeBounds = readBounds(1);
        const mainWholeBounds = readBounds(2);
        const importNarrowBounds = readBounds(3);
        const defsNarrowBounds = readBounds(4);
        const mainNarrowBounds = readBounds(5);
        let boundsToUse = [];
        // If we have stuff elsewhere we use whole bounds, otherwise just the container:
        if (hasImports) boundsToUse.push(hasDefs || hasMain ? importWholeBounds : importNarrowBounds);
        if (hasDefs) boundsToUse.push(hasImports || hasMain ? defsWholeBounds : defsNarrowBounds);
        if (hasMain) boundsToUse.push(hasImports || hasDefs ? mainWholeBounds : mainNarrowBounds);
        let totalRect = boundsToUse.reduce(getUnion);
        //console.log("Capture: " + JSON.stringify(totalRect));
        await captureRect(testWin, integerRect(totalRect), zoom, destFilename);
        // If all goes well, we should  output this, the filename written to, on FD 3:
        try {
            writeSync(3, destFilename);
        }
        catch (err) {
            // Windows doesn't support FD 3
        }
        testWin.close();
        // Exit forces it (unlike app.quit):
        app.exit();
    });
});
