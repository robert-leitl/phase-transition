import { take, debounceTime, fromEvent } from 'rxjs';
import { Sketch } from './sketch';
import { Pane } from 'tweakpane';
import * as modernizr from './utils/modernizr';

const queryString = window.location.search;
const urlParams = new URLSearchParams(queryString);
const hasDebugParam = urlParams.get('debug');
const isDev = import.meta.env.MODE === 'development';
let sketch;
let pane;

if (isDev) {
    import('https://greggman.github.io/webgl-lint/webgl-lint.js');
}

if (hasDebugParam || isDev) {
    //pane = new Pane({ title: 'Settings', expanded: isDev });
}

const resize = () => {
    // explicitly set the width and height to compensate for missing dvh and dvw support
    document.body.style.width = `${document.documentElement.clientWidth}px`;
    document.body.style.height = `${document.documentElement.clientHeight}px`;

    if (sketch) {
        sketch.resize();
    }
}

// add a debounced resize listener
fromEvent(window, 'resize').pipe(debounceTime(100)).subscribe(() => resize());

// resize initially on load
fromEvent(window, 'load').pipe(take(1)).subscribe(() => resize());

// INIT APP
const canvasElm = document.querySelector('canvas');
const startButton = document.querySelector('#start-button');
const intro = document.querySelector('#intro');

sketch = new Sketch(canvasElm, (instance) => {
    startButton.style.opacity = 1;
    document.body.removeChild(document.body.querySelector('#loader'));
    fromEvent(startButton, 'click').pipe(take(1)).subscribe(() => {
        intro.style.display = 'none';
        startButton.style.display = 'none';
        instance.run();
    });
}, isDev, pane);
