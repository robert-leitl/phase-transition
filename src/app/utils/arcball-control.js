import { quat, vec3, vec2, mat3 } from 'gl-matrix';

export class ArcballControl {

    // the current rotation quaternion
    rotationQuat = quat.create();

    constructor(canvas, updateCallback) {
        this.canvas = canvas;
        this.updateCallback = updateCallback ? updateCallback : () => null;

        this.pointerDown = false;
        this.pointerDownPos = vec2.create();
        this.pointerPos = vec2.create();
        this.followPos = vec3.create();
        this.prevFollowPos = vec3.create();
        this.autoRotationSpeed = 0;
        this.velocity = 0.002;
        this.rotationAxis = vec3.fromValues(0, 1, 0);

        canvas.style.touchAction = 'none';

        canvas.addEventListener('pointerdown', e => {
            this.pointerDownPos = vec2.fromValues(e.clientX, e.clientY);
            this.followPos = vec3.fromValues(e.clientX, e.clientY, 0);
            this.pointerPos = vec2.fromValues(e.clientX, e.clientY);
            this.prevFollowPos = vec3.fromValues(e.clientX, e.clientY, 0);
            this.pointerDown = true;
            this.autoRotationSpeed = 0;
        });
        canvas.addEventListener('pointerup', e => {
            this.pointerDown = false;
        });
        canvas.addEventListener('pointerleave', e => {
            this.pointerDown = false;
        });
        canvas.addEventListener('pointermove', e => {
            if (this.pointerDown) {
                this.pointerPos[0] = e.clientX;
                this.pointerPos[1] = e.clientY;
            }
        });
    }

    update(deltaTime) {
        const timeScale = 16 / (deltaTime + 0.01);

        // the mouse follower
        const damping = 10 * timeScale;
        this.followPos[0] += (this.pointerPos[0] - this.followPos[0]) / damping;
        this.followPos[1] += (this.pointerPos[1] - this.followPos[1]) / damping;

        let r;
        if (this.pointerDown) {
            // get points on the arcball and corresponding normals
            const p = this.#project(this.followPos);
            const q = this.#project(this.prevFollowPos);
            const np = vec3.normalize(vec3.create(), p);
            const nq = vec3.normalize(vec3.create(), q);

            // get the normalized axis of rotation
            const axis = vec3.cross(vec3.create(), p, q);
            vec3.normalize(axis, axis);

            // get the amount of rotation
            const d = Math.max(-1, Math.min(1, vec3.dot(np, nq)));
            const angle = Math.acos(d) * timeScale * 3;

            this.velocity = angle;
            this.rotationAxis = vec3.clone(axis);

            // get the new rotation quat
            r = quat.setAxisAngle(quat.create(), axis, angle);
        } else {
            this.velocity *= this.velocity > 0.002 ? .97 : 1;
            //r = quat.setAxisAngle(quat.create(), vec3.fromValues(0, 1, 0), this.autoRotationSpeed);
            r = quat.setAxisAngle(quat.create(), this.rotationAxis, this.velocity);
        }

        // apply the new rotation to the current rotation and normalize
        quat.multiply(this.rotationQuat, r, this.rotationQuat);
        quat.normalize(this.rotationQuat, this.rotationQuat);

        // update for the next iteration
        this.prevFollowPos = vec3.clone(this.followPos);
        this.updateCallback();
    }

    /**
     * Maps pointer coordinates to canonical coordinates [-1, 1] 
     * and projects them onto the arcball surface or onto a 
     * hyperbolical function outside the arcball.
     * 
     * @return vec3 The arcball coords
     * 
     * @see https://www.xarg.org/2021/07/trackball-rotation-using-quaternions/
     */
    #project(pos) {
        const r = 1; // arcball radius
        const w = this.canvas.clientWidth;
        const h = this.canvas.clientHeight;
        const s = Math.max(w, h) - 1;

        // map to -1 to 1
        const x = (2 * pos[0] - w - 1) / s;
        const y = (2 * pos[1] - h - 1) / s;
        let z = 0;
        const xySq = x * x + y * y;
        const rSq = r * r;

        if (xySq <= rSq / 2)
            z = Math.sqrt(rSq - xySq);
        else
            z = (rSq / 2) / Math.sqrt(xySq); // hyperbolical function

        return vec3.fromValues(-x, y, z);
    }
}