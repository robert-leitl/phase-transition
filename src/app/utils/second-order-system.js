/**
 * Second order system value for procedural animation with target values (https://www.youtube.com/watch?v=KPoeNZZ6H4s).
 */
class SecondOrderSystemValue {
  
    // the current value of the system
    #y;
    
    // the current velocity of the system
    #yd; 
    
    // the previous target value
    #xp; 
    
    // constants derived from the frequency, damping and response factors
    #k1; #k2; #k3;
    
    /**
     * Creates a new second order system for a single value.
     *
     * @param f The frequency value (f > 0)
     * @param z The damping factor (0 = no damping, 0 < damping < 1 = underdamped -> vibration, > 1 = no vibration)
     * @param r The response factor (0 = slow acceleration, 0 < response < 1 = immediate response, r > 1 = overshoot, r < 0 = anticipate motion / wind up)
     * @param x0 The initial target value
     */
    constructor(f, z, r, x0) {
      this.#y = x0;
      this.#xp = x0;
      this.#yd = 0;
      
      this.#k1 = z / (Math.PI * f);
      this.#k2 = 1 / ((2 * Math.PI * f) * (2 * Math.PI * f));
      this.#k3 = (r * z) / (2 * Math.PI * f);
    }
    
    update(dt, x, xd) {
      // estimate the target velocity
      if (xd == null) {
        xd = (x - this.#xp) / dt;
        this.#xp = x;
      }
      
      // integrate position by velocity
      this.#y += this.#yd * dt;
      
      // clamp k2 for stability
      const k2 = Math.max(this.#k2, 1.1 * ((dt * dt) / 4 + (dt * this.#k1) / 2));
      
      // update the acceleration
      const ydd = (x + this.#k3 * xd - this.#y - this.#k1 * this.#yd) / k2;
      
      // integrate velocity by acceleration
      this.#yd += ydd * dt;
      
      return this.#y;
    }
    
    get value() {
      return this.#y;
    }
  }