const { app, BrowserWindow, clipboard} = require('electron')
const {join} = require("node:path");
const {writeFileSync, readFileSync, existsSync} = require("node:fs");
const crypto = require('crypto');

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

const zoom = 2.5;

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
const destFilename = 'strype-' + crypto.createHash('md5').update(completeSource).digest('hex') + '.png';

if (existsSync(destFilename)) {
    console.log("File already exists, not regenerating.");
    app.exit(1);
}

const allLines = completeSource.split(/\r?\n/);

// Find first zero-indent line that is not blank or import or def:
let firstMain = allLines.findIndex(s => !s.match(/^(($)|(import\s+.*)|(from\s+.*)|(def\s+.*)|(#.*)|(\s+.*))/));
// Also include preceding blanks and left-aligned comments:
while (firstMain > 0 && allLines[firstMain - 1].match(/^((\s*$)|#.*)/)) {firstMain -= 1;}
const main = firstMain === -1 ? null : allLines.slice(firstMain);
const lastImport = allLines.findLastIndex(s => s.match(/^((import\s+)|(from\s+))/));
const imports = lastImport === -1 ? null : allLines.slice(0, lastImport + 1);
const defs = firstMain === lastImport + 1 ? null : allLines.slice(lastImport === -1 ? 0 : lastImport + 1, firstMain === -1 ? allLines.length : firstMain);

app.on('ready', async () => {
    const testWin = new BrowserWindow({
        width: 1920,
        height: 1080 * 3,
        // Don't actually show the GUI (can toggle for debugging):
        show: false,
        webPreferences: {
            // Must turn off sandbox to be able to write image files:
            sandbox: false,
            offscreen: true
        },
    });

    // Must get rid of old data to revert to basic project:
    await testWin.webContents.session.clearCache(function(){});
    await testWin.webContents.session.clearStorageData();


    function sendKey(entry, delay)
    {
        ["keyDown", "keyUp"].forEach(async(type) =>
        {
            entry.type = type;
            testWin.webContents.sendInputEvent(entry);

            // Delay
            await new Promise(resolve => setTimeout(resolve, delay));
        });
    }

    const {clipboard} = require('electron');


    await testWin.loadURL("https://strype.org/test/editor/"); // TODO set back to main
    testWin.webContents.on('did-stop-loading', async() => {
        testWin.webContents.setZoomFactor(zoom);
        sendKey({keyCode: "Delete"}, 100);
        sendKey({keyCode: "Delete"}, 100);
        sendKey({keyCode: "up"}, 100);
        sendKey({keyCode: "up"}, 100);
        if (imports) {
            clipboard.writeText(imports.filter(s => s.trim()).join('\n'));
            console.log("Pasting imports: " + clipboard.readText());
            await testWin.webContents.executeJavaScript("document.execCommand('paste');");

        }
        sendKey({keyCode: "down"}, 100);
        if (defs) {
            clipboard.writeText(defs.filter(s => s.trim()).join('\n'));
            console.log("Pasting defs: " + clipboard.readText());
            await testWin.webContents.executeJavaScript("document.execCommand('paste');");
        }
        sendKey({keyCode: "down"}, 100);
        if (main) {
            clipboard.writeText(main.join('\n'));
            console.log("Pasting main: " + clipboard.readText());
            await testWin.webContents.executeJavaScript("document.execCommand('paste');");
        }


        // Need to wait for re-render after adjusting zoom and sending paste:
        setTimeout(function() {
            Promise.all([
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-1').getBoundingClientRect().x"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-1').getBoundingClientRect().y"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-1').getBoundingClientRect().width"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-1').getBoundingClientRect().height + 10"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-2').getBoundingClientRect().x"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-2').getBoundingClientRect().y"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-2').getBoundingClientRect().width"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-2').getBoundingClientRect().height + 10"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-3').getBoundingClientRect().x"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-3').getBoundingClientRect().y"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-3').getBoundingClientRect().width"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-3').getBoundingClientRect().height - 190")
            ])
                .then((allBounds) => {
                    //console.log("Bounds: " +
                    const importBounds = {
                        x: zoom * allBounds[0],
                        y: zoom * allBounds[1],
                        width: zoom * allBounds[2],
                        height: zoom * allBounds[3]
                    };
                    const defsBounds = {
                        x: zoom * allBounds[4],
                        y: zoom * allBounds[5],
                        width: zoom * allBounds[6],
                        height: zoom * allBounds[7]
                    };
                    const mainBounds = {
                        x: zoom * allBounds[8],
                        y: zoom * allBounds[9],
                        width: zoom * allBounds[10],
                        height: zoom * allBounds[11]
                    };
                    let boundsToUse = [];
                    if (imports) boundsToUse.push(importBounds);
                    if (defs) boundsToUse.push(defsBounds);
                    if (main) boundsToUse.push(mainBounds);
                    testWin.webContents.capturePage(boundsToUse.reduce(getUnion)).then((img) => {
                        writeFileSync(destFilename, img.toPNG());
                        testWin.close();
                        // Exit forces it (unlike quit):
                        app.exit();
                    });
                });
        }, 2000);
    });
});
