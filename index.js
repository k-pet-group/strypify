const { app, BrowserWindow } = require('electron')
const {join} = require("node:path");
const {writeFileSync} = require("node:fs");

const zoom = 2.5;

app.on('ready', () => {
    const testWin = new BrowserWindow({
        width: 1920,
        height: 1080,
        // Don't actually show the GUI (can toggle for debugging):
        show: false,
        webPreferences: {
            // Must turn off sandbox to be able to write image files:
            sandbox: false,
        },
    });

    testWin.loadURL("https://strype.org/editor/");
    testWin.webContents.on('did-stop-loading', async() => {
        testWin.webContents.setZoomFactor(zoom);
        // Need to wait for re-render after adjusting zoom:
        setTimeout(function() {
            Promise.all([
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-2').getBoundingClientRect().x"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-2').getBoundingClientRect().y"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-2').getBoundingClientRect().width"),
                testWin.webContents.executeJavaScript("document.getElementById('FrameContainer_-2').getBoundingClientRect().height")
            ])
                .then((bounds) => {
                    console.log("Bounds: " + JSON.stringify(bounds));
                    testWin.webContents.capturePage({
                        x: zoom * bounds[0],
                        y: zoom * bounds[1],
                        width: zoom * bounds[2],
                        height: zoom * bounds[3]
                    }).then((img) => {
                        const previewImgUrl = join(__dirname, 'preview-capture-image.png');
                        writeFileSync(previewImgUrl, img.toPNG());
                        testWin.close();
                    });
                });
        }, 500);
    });
});
