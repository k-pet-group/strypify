const { app, BrowserWindow, clipboard} = require('electron')
const {writeSync, readFileSync, existsSync} = require("node:fs");
const crypto = require('crypto');
const sharp = require('sharp');

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
    const captureWidth = Math.min(viewportWidth, rect.width);
    for (let offsetY = 0; offsetY < rect.height; offsetY += viewportHeight) {
        // targetScrollY is device pixels:
        const targetScrollY = rect.y + offsetY;
        const captureHeight = Math.min(viewportHeight, rect.height - offsetY);

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
// Filename is predetermined by the MD5 hash of the code.  This helps with caching the image to avoid
// unnecessary regeneration.
const destFilename = 'strype-' + crypto.createHash('md5').update(completeSource).digest('hex') + '.png';

if (existsSync(destFilename)) {
    console.log("File already exists, not regenerating.");
    app.exit(1);
}

const allLines = completeSource.split(/\r?\n/);

// Find first zero-indent line that is not blank or import or def:
let firstMain = allLines.findIndex(s => !s.match(/^(($)|(import\s+.*)|(from\s+.*)|(def\s+.*)|(#.*)|(\s+.*))/));
// Also include preceding blanks and left-aligned comments:
while (firstMain > 0 && allLines[firstMain - 1].match(/^((\s*$)|#.*)/)) {
    firstMain -= 1;
}
const main = firstMain === -1 ? null : allLines.slice(firstMain);
const lastImport = allLines.findLastIndex(s => s.match(/^((import\s+)|(from\s+))/));
const imports = lastImport === -1 ? null : allLines.slice(0, lastImport + 1);
const defs = firstMain === lastImport + 1 ? null : allLines.slice(lastImport === -1 ? 0 : lastImport + 1, firstMain === -1 ? allLines.length : firstMain);

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
            offscreen: !debugging
        },
    });

    // Must get rid of old data to revert to basic project:
    await testWin.webContents.session.clearCache(function(){});
    await testWin.webContents.session.clearStorageData();

    async function sendKey(entry, delay)
    {
        await Promise.all(["keyDown", "keyUp"].map(async(type) =>
        {
            entry.type = type;
            testWin.webContents.sendInputEvent(entry);

            // Delay
            await new Promise(resolve => setTimeout(resolve, delay));
        }));
    }


    await testWin.loadURL("https://strype.org/editor/");
    testWin.webContents.on('did-stop-loading', async() => {
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
        // Clear current code and go up to imports:
        await sendKey({keyCode: "Delete"}, 100);
        await sendKey({keyCode: "Delete"}, 100);
        await sendKey({keyCode: "up"}, 100);
        await sendKey({keyCode: "up"}, 100);
        if (imports) {
            clipboard.writeText(imports.filter(s => s.trim()).join('\n'));
            //console.log("Pasting imports: " + clipboard.readText());
            await testWin.webContents.executeJavaScript("document.execCommand('paste');");

        }
        await sendKey({keyCode: "down"}, 100);
        if (defs) {
            clipboard.writeText(defs.filter(s => s.trim()).join('\n'));
            //console.log("Pasting defs: " + clipboard.readText());
            await testWin.webContents.executeJavaScript("document.execCommand('paste');");
        }
        await sendKey({keyCode: "down"}, 100);
        if (main) {
            clipboard.writeText(main.join('\n'));
            //console.log("Pasting main: " + clipboard.readText());
            await testWin.webContents.executeJavaScript("document.execCommand('paste');");
        }

        // Need to wait for re-render after adjusting zoom and sending paste:
        setTimeout(function() {
            // Scroll to top of page:
            testWin.webContents.executeJavaScript(`document.getElementById("editorCodeDiv").scrollTo(0, 0)`)
                .then(() =>new Promise(resolve => setTimeout(resolve, 200)))// allow rendering
                .then(() => {

                // Could probably do this simpler, but had problems initially getting more complex objects
                // back from executeJavaScript, so we do it one primitive number at a time:
                Promise.all([
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-1', 10)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-2', 10)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-3', -190)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-1 > .container-frames', 0)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-2 > .container-frames', 0)"),
                    testWin.webContents.executeJavaScript("window.getUnionBoundsAsSemiStr('#frameContainer_-3 > .container-frames', 0)"),
                ])
                    .then((allBounds) => {
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
                        if (imports) boundsToUse.push(defs || main ? importWholeBounds : importNarrowBounds);
                        if (defs) boundsToUse.push(imports || main ? defsWholeBounds : defsNarrowBounds);
                        if (main) boundsToUse.push(imports || defs ? mainWholeBounds : mainNarrowBounds);
                        let totalRect = boundsToUse.reduce(getUnion);
                        //console.log("Capture: " + JSON.stringify(totalRect));
                        captureRect(testWin, integerRect(totalRect), zoom, destFilename).then(() => {
                            // If all goes well, we should  output this, the filename written to, on FD 3:
                            try {
                                writeSync(3, destFilename);
                            } catch (err) {
                            }
                            testWin.close();
                            // Exit forces it (unlike app.quit):
                            app.exit();
                        });
                    });
            });
        }, 2000);
    });
});
