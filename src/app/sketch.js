import { mat4, vec2, vec3, vec4 } from "gl-matrix";
import { filter, fromEvent, merge, throwIfEmpty } from "rxjs";
import * as twgl from "twgl.js";
import { GLBBuilder } from "./utils/glb-builder";
import { ArcballControl } from "./utils/arcball-control";

import colorVert from './shader/color.vert.glsl';
import colorFrag from './shader/color.frag.glsl';
import textureVert from './shader/texture.vert.glsl';
import textureFrag from './shader/texture.frag.glsl';
import testVert from './shader/test.vert.glsl';
import testFrag from './shader/test.frag.glsl';
import highpassVert from './shader/highpass.vert.glsl';
import highpassFrag from './shader/highpass.frag.glsl';
import blurVert from './shader/blur.vert.glsl';
import blurFrag from './shader/blur.frag.glsl';
import compositeVert from './shader/composite.vert.glsl';
import compositeFrag from './shader/composite.frag.glsl';
import { easeInOutCubic, easeInOutExpo } from "./utils";

export class Sketch {

    TARGET_FRAME_DURATION = 16;
    #time = 0; // total time
    #deltaTime = 0; // duration betweent the previous and the current animation frame
    #frames = 0; // total framecount according to the target frame duration
    // relative frames according to the target frame duration (1 = 60 fps)
    // gets smaller with higher framerates --> use to adapt animation timing
    #deltaFrames = 0;
    
    // the scale factor for the bloom and lensflare highpass texture
    SS_FX_SCALE = 0.2;

    // animation properties
    TRANSITION_DURATION = 60;

    camera = {
        matrix: mat4.create(),
        near: 0.1,
        far: 5,
        fov: Math.PI / 3,
        aspect: 1,
        position: vec3.fromValues(0, 0, 3),
        up: vec3.fromValues(0, 1, 0),
        matrices: {
            view: mat4.create(),
            projection: mat4.create(),
            inversProjection: mat4.create(),
            inversViewProjection: mat4.create()
        }
    };

    settings = {
        progress: 0
    }
    
    constructor(canvasElm, onInit = null, isDev = false, pane = null) {
        this.canvas = canvasElm;
        this.onInit = onInit;
        this.isDev = isDev;
        this.pane = pane;

        this.#init().then(() => {
            if (this.onInit) this.onInit(this)
        });
    }

    run(time = 0) {
        this.#deltaTime = Math.min(16, time - this.#time);
        this.#time = time;
        this.#deltaFrames = this.#deltaTime / this.TARGET_FRAME_DURATION;
        this.#frames += this.#deltaFrames;

        this.control.update(this.#deltaTime);
        mat4.fromQuat(this.worldMatrix, this.control.rotationQuat);

        // update the world inverse transpose
        mat4.invert(this.worldInverseMatrix, this.worldMatrix);
        mat4.transpose(this.worldInverseTransposeMatrix, this.worldInverseMatrix);

        this.#animate(this.#deltaTime);
        this.#render();

        requestAnimationFrame((t) => this.run(t));
    }

    resize() {
        /** @type {WebGLRenderingContext} */
        const gl = this.gl;

        this.viewportSize = vec2.set(
            this.viewportSize,
            this.canvas.clientWidth,
            this.canvas.clientHeight
        );

        const needsResize = twgl.resizeCanvasToDisplaySize(this.canvas);

        if (needsResize) {
            gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);

            if (this.highpassFBO) {
                twgl.resizeFramebufferInfo(gl, this.highpassFBO, [{attachmentPoint: gl.COLOR_ATTACHMENT0}], 
                    this.viewportSize[0] * this.SS_FX_SCALE, this.viewportSize[1] * this.SS_FX_SCALE);
            }

            if (this.blurFBO) {
                twgl.resizeFramebufferInfo(gl, this.blurFBO, [{attachmentPoint: gl.COLOR_ATTACHMENT0}], 
                    this.viewportSize[0] * this.SS_FX_SCALE, this.viewportSize[1] * this.SS_FX_SCALE);
            }

            if (this.drawFBO) {
                twgl.resizeFramebufferInfo(gl, this.drawFBO, [
                    {attachmentPoint: gl.COLOR_ATTACHMENT0},
                    {attachmentPoint: gl.DEPTH_ATTACHMENT, format: gl.DEPTH_COMPONENT, internalFormat: gl.DEPTH_COMPONENT32F}
                ], this.viewportSize[0], this.viewportSize[1]);
            }
        }

        this.#updateProjectionMatrix(gl);
    }

    async #init() {
        this.gl = this.canvas.getContext('webgl2', { antialias: false, alpha: false });

        this.touchevents = Modernizr.touchevents;

        /** @type {WebGLRenderingContext} */
        const gl = this.gl;

        twgl.addExtensionsToContext(gl);

        this.viewportSize = vec2.fromValues(
            this.canvas.clientWidth,
            this.canvas.clientHeight
        );

        await this.#initImageTextures();

        // Setup Programs
        this.colorPrg = twgl.createProgramInfo(gl, [colorVert, colorFrag]);
        this.texturePrg = twgl.createProgramInfo(gl, [textureVert, textureFrag]);
        this.testPrg = twgl.createProgramInfo(gl, [testVert, testFrag]);
        this.highpassPrg = twgl.createProgramInfo(gl, [highpassVert, highpassFrag]);
        this.blurPrg = twgl.createProgramInfo(gl, [blurVert, blurFrag]);
        this.compositePrg = twgl.createProgramInfo(gl, [compositeVert, compositeFrag]);

        // Setup Meshes
        this.quadBufferInfo = twgl.createBufferInfoFromArrays(gl, { a_position: { numComponents: 2, data: [-1, -1, 3, -1, -1, 3] }});
        this.quadVAO = twgl.createVAOAndSetAttributes(gl, this.texturePrg.attribSetters, this.quadBufferInfo.attribs, this.quadBufferInfo.indices);

        // load the bead model
        this.glbBuilder = new GLBBuilder(gl);
        await this.glbBuilder.load(new URL('../assets/model.glb', import.meta.url));
        console.log(this.glbBuilder);
        this.modelPrimitive = this.glbBuilder.getPrimitiveDataByMeshName('Icosphere');
        this.modelBuffers = this.modelPrimitive.buffers;
        this.modelBufferInfo = twgl.createBufferInfoFromArrays(gl, { 
            a_position: {...this.modelBuffers.vertices, numComponents: this.modelBuffers.vertices.numberOfComponents},
            a_normal: {...this.modelBuffers.normals, numComponents: this.modelBuffers.normals.numberOfComponents},
            a_texcoord: {...this.modelBuffers.texcoords, numComponents: this.modelBuffers.texcoords.numberOfComponents},
            a_tangent: {...this.modelBuffers.tangents, numComponents: this.modelBuffers.tangents.numberOfComponents},
            indices: {...this.modelBuffers.indices, numComponents: this.modelBuffers.indices.numberOfComponents}
        });
        this.modelVAO = twgl.createVAOAndSetAttributes(gl, this.colorPrg.attribSetters, this.modelBufferInfo.attribs, this.modelBufferInfo.indices);

        // Setup Framebuffers
        const resScale = Math.max(this.viewportSize[0], this.viewportSize[1]) > 800 ? 1 : 0.5;
        console.log(resScale);
        this.textureFBO = twgl.createFramebufferInfo(
            gl, 
            [{attachmentPoint: gl.COLOR_ATTACHMENT0}, {attachmentPoint: gl.COLOR_ATTACHMENT1}], 
            2048 * resScale, 1024 * resScale
        );
        this.iceTexture = this.textureFBO.attachments[0];
        this.iceNormalTexture = this.textureFBO.attachments[1];
        this.drawFBO = twgl.createFramebufferInfo(gl, [
            {attachmentPoint: gl.COLOR_ATTACHMENT0},
            {attachmentPoint: gl.DEPTH_ATTACHMENT, format: gl.DEPTH_COMPONENT, internalFormat: gl.DEPTH_COMPONENT32F}
        ], this.viewportSize[0], this.viewportSize[1]);
        this.colorTexture = this.drawFBO.attachments[0];
        this.highpassFBO = twgl.createFramebufferInfo(
            gl, 
            [{attachmentPoint: gl.COLOR_ATTACHMENT0}], 
            this.viewportSize[0] * this.SS_FX_SCALE,
            this.viewportSize[1] * this.SS_FX_SCALE
        );
        this.highpassTexture = this.highpassFBO.attachments[0];
        this.blurFBO = twgl.createFramebufferInfo(
            gl, 
            [{attachmentPoint: gl.COLOR_ATTACHMENT0}], 
            this.viewportSize[0] * this.SS_FX_SCALE,
            this.viewportSize[1] * this.SS_FX_SCALE
        );
        this.blurTexture = this.blurFBO.attachments[0];

        this.worldMatrix = mat4.create();
        this.worldInverseMatrix = mat4.create();
        this.worldInverseTransposeMatrix = mat4.create();
        
        this.progress = 0;
        this.control = new ArcballControl(this.canvas);
        this.#initTweakpane();
        this.#updateCameraMatrix();
        this.#updateProjectionMatrix(gl);
        this.#initEvents();

        this.resize();
    }

    #initEvents() {
        this.isPointerDown = false;

        fromEvent(this.canvas, 'pointerdown').subscribe((e) => {
            this.isPointerDown = true;
        });
        merge(
            fromEvent(this.canvas, 'pointerup'),
            fromEvent(this.canvas, 'pointerleave')
        ).subscribe(() => this.isPointerDown = false);
    }

    #initImageTextures() {
        /** @type {WebGLRenderingContext} */
        const gl = this.gl;

        const dirtTexturePromise = new Promise((resolve) => {
            this.dirtTexture = twgl.createTexture(gl, {
                src: new URL('../assets/dirt.jpg', import.meta.url).toString(),
            }, () => resolve());
        });

        const concreteTexturePromise = new Promise((resolve) => {
            this.concreteTexture = twgl.createTexture(gl, {
                src: new URL('../assets/concrete.jpg', import.meta.url).toString(),
            }, () => resolve());
        });

        const envMapPromise = new Promise(resolve => {
            this.envMapTexture = twgl.createTexture(gl, {
                target: gl.TEXTURE_CUBE_MAP,
                src: [
                    new URL('../assets/env/posx.jpg', import.meta.url).toString(),
                    new URL('../assets/env/negx.jpg', import.meta.url).toString(),
                    new URL('../assets/env/posy.jpg', import.meta.url).toString(),
                    new URL('../assets/env/negy.jpg', import.meta.url).toString(),
                    new URL('../assets/env/posz.jpg', import.meta.url).toString(),
                    new URL('../assets/env/negz.jpg', import.meta.url).toString(),
                ],
            }, () => resolve())
        })

        return Promise.all([dirtTexturePromise]);
    }

    #initTweakpane() {
        if (!this.pane) return;

        this.animationFolder = this.pane.addFolder({ title: 'Animation', expanded: true });
        this.animationFolder.addInput(
            this.settings, 
            'progress',
            { label: 'progress', min: 0, max: 1 }
        );
    }

    #animate(deltaTime) {
        /** @type {WebGLRenderingContext} */
        const gl = this.gl;

        // use a fixed deltaTime of 10 ms adapted to
        // device frame rate
        deltaTime = 16 * this.#deltaFrames;

        this.progress += (this.isPointerDown ? -1 : 2) * deltaTime * 0.00025;
        this.progress = Math.min(1.5, Math.max(0, this.progress));
        this.settings.progress = Math.min(1, Math.max(0, this.progress));
    }

    #render() {
        /** @type {WebGLRenderingContext} */
        const gl = this.gl;

        // render the texture
        if (!this.prerender) {
            this.prerender = true;
            twgl.bindFramebufferInfo(gl, this.textureFBO);
            gl.bindVertexArray(this.quadVAO);
            gl.disable(gl.CULL_FACE);
            gl.disable(gl.DEPTH_TEST);
            this.gl.clearColor(0, 0, 0, 1);
            this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);
            this.gl.useProgram(this.texturePrg.program);
            twgl.setUniforms(this.texturePrg, {
                u_concreteTexture: this.concreteTexture
            });
            twgl.drawBufferInfo(gl, this.quadBufferInfo);
        }

        const p = this.settings.progress;
        twgl.bindFramebufferInfo(gl, this.drawFBO );
        this.gl.clearColor(0, 0, 0, 1);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT | this.gl.DEPTH_BUFFER_BIT);
        this.gl.useProgram(this.colorPrg.program);
        twgl.setUniforms(this.colorPrg, {
            u_worldMatrix: this.worldMatrix,
            u_viewMatrix: this.camera.matrices.view,
            u_projectionMatrix: this.camera.matrices.projection,
            u_worldInverseTransposeMatrix: this.worldInverseTransposeMatrix,
            u_worldInverseMatrix: this.worldInverseMatrix,
            u_cameraPos: this.camera.position,
            u_time: this.#time,
            u_iceTexture: this.iceTexture,
            u_iceNormal: this.iceNormalTexture,
            u_dirtTexture: this.dirtTexture,
            u_envMapTexture: this.envMapTexture,
            u_progress1: 1 - Math.pow((1-p), 5),
            u_progress2: easeInOutCubic(p),
            u_progress3: easeInOutExpo(Math.max(0, (p - 0.5) * 2))
        });
        gl.bindVertexArray(this.modelVAO);
        gl.enable(gl.CULL_FACE);
        gl.enable(gl.DEPTH_TEST);
        gl.drawElements(
            gl.TRIANGLES,
            this.modelBufferInfo.numElements,
            gl.UNSIGNED_SHORT,
            0
        );

        // get highpass
        twgl.bindFramebufferInfo(gl, this.highpassFBO);
        gl.bindVertexArray(this.quadVAO);
        gl.useProgram(this.highpassPrg.program);
        twgl.setUniforms(this.highpassPrg, { 
            u_colorTexture: this.colorTexture
        });
        twgl.drawBufferInfo(gl, this.quadBufferInfo);

        // blur pass
        twgl.bindFramebufferInfo(gl, this.blurFBO);
        gl.bindVertexArray(this.quadVAO);
        gl.useProgram(this.blurPrg.program);
        twgl.setUniforms(this.blurPrg, { 
            u_colorTexture: this.highpassTexture
        });
        twgl.drawBufferInfo(gl, this.quadBufferInfo);

        // composite the final image
        twgl.bindFramebufferInfo(gl, null);
        gl.viewport(0, 0, this.viewportSize[0], this.viewportSize[1]);
        gl.bindVertexArray(this.quadVAO);
        gl.useProgram(this.compositePrg.program);
        twgl.setUniforms(this.compositePrg, { 
            u_bloomTexture: this.blurTexture,
            u_colorTexture: this.colorTexture,
            u_stainTexture: this.concreteTexture
        });
        twgl.drawBufferInfo(gl, this.quadBufferInfo);


        if (this.isDev) {
            // draw helper view of particle texture
            /*twgl.bindFramebufferInfo(gl, null);
            gl.viewport(0, 0, this.viewportSize[0] / 2, this.viewportSize[1] / 4);
            gl.bindVertexArray(this.quadVAO);
            gl.disable(gl.DEPTH_TEST);
            gl.useProgram(this.testPrg.program);
            twgl.setUniforms(this.testPrg, { 
                u_texture: this.iceNormalTexture
            });
            twgl.drawBufferInfo(gl, this.quadBufferInfo);*/
        }
    }

    #updateCameraMatrix() {
        mat4.targetTo(this.camera.matrix, this.camera.position, [0, 0, 0], this.camera.up);
        mat4.invert(this.camera.matrices.view, this.camera.matrix);
    }

    #updateProjectionMatrix(gl) {
        this.camera.aspect = gl.canvas.clientWidth / gl.canvas.clientHeight;

        const height = 1.3;
        const distance = this.camera.position[2];
        if (this.camera.aspect > 1) {
            this.camera.fov = 2 * Math.atan( height / distance );
        } else {
            this.camera.fov = 2 * Math.atan( (height / this.camera.aspect) / distance );
        }

        mat4.perspective(this.camera.matrices.projection, this.camera.fov, this.camera.aspect, this.camera.near, this.camera.far);
        mat4.invert(this.camera.matrices.inversProjection, this.camera.matrices.projection);
        mat4.multiply(this.camera.matrices.inversViewProjection, this.camera.matrix, this.camera.matrices.inversProjection)
    }
}