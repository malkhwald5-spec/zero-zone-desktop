'use strict';

// On-screen controls in the style of mobile battle royales: a movement joystick
// on the left (push it far up to lock sprint), drag anywhere on the right to look,
// and action buttons. Works with touch and with a mouse.
(() => {
  const ZZ = window.ZZ;
  const $ = (id) => document.getElementById(id);

  const Touch = {
    enabled: false,
    move: { x: 0, y: 0 },
    sprintLock: false,
    handlers: null,

    init(handlers) {
      this.handlers = handlers;
      const root = $('touch');
      const joy = $('joy'), knob = $('joy-knob'), sprint = $('joy-sprint');
      const R = 52;
      let joyId = null, joyCx = 0, joyCy = 0;

      const setKnob = (dx, dy) => { knob.style.transform = `translate(${dx}px, ${dy}px)`; };
      joy.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        joyId = e.pointerId;
        joy.setPointerCapture(e.pointerId);
        const r = joy.getBoundingClientRect();
        joyCx = r.left + r.width / 2; joyCy = r.top + r.height / 2;
        this.sprintLock = false;
        sprint.classList.remove('on');
        onJoy(e);
      });
      const onJoy = (e) => {
        if (e.pointerId !== joyId) return;
        let dx = e.clientX - joyCx, dy = e.clientY - joyCy;
        // Dragging well past the top of the ring locks sprint.
        this.sprintLock = dy < -R * 1.9 && Math.abs(dx) < R;
        sprint.classList.toggle('on', this.sprintLock);
        const d = Math.hypot(dx, dy);
        if (d > R) { dx = (dx / d) * R; dy = (dy / d) * R; }
        setKnob(dx, dy);
        this.move.x = dx / R; this.move.y = dy / R;
      };
      joy.addEventListener('pointermove', onJoy);
      const endJoy = (e) => {
        if (e.pointerId !== joyId) return;
        joyId = null;
        if (this.sprintLock) { this.move.x = 0; this.move.y = -1; setKnob(0, -R); return; }
        this.move.x = this.move.y = 0;
        setKnob(0, 0);
      };
      joy.addEventListener('pointerup', endJoy);
      joy.addEventListener('pointercancel', endJoy);
      // Tapping the sprint badge releases the sprint lock.
      sprint.addEventListener('pointerdown', (e) => {
        e.stopPropagation();
        this.releaseSprint();
      });

      // Look: drag on the free area of the screen.
      const pad = $('look-pad');
      const lookIds = new Map();
      pad.addEventListener('pointerdown', (e) => {
        lookIds.set(e.pointerId, { x: e.clientX, y: e.clientY });
        pad.setPointerCapture(e.pointerId);
      });
      pad.addEventListener('pointermove', (e) => {
        const last = lookIds.get(e.pointerId);
        if (!last) return;
        this.handlers.look(e.clientX - last.x, e.clientY - last.y);
        last.x = e.clientX; last.y = e.clientY;
      });
      const endLook = (e) => lookIds.delete(e.pointerId);
      pad.addEventListener('pointerup', endLook);
      pad.addEventListener('pointercancel', endLook);

      // Buttons. Fire buttons also turn the camera while held, like on mobile.
      root.querySelectorAll('[data-act]').forEach((btn) => {
        const act = btn.dataset.act;
        let last = null;
        btn.addEventListener('pointerdown', (e) => {
          e.preventDefault();
          e.stopPropagation();
          btn.setPointerCapture(e.pointerId);
          btn.classList.add('down');
          last = { x: e.clientX, y: e.clientY };
          this.handlers.action(act, true);
        });
        btn.addEventListener('pointermove', (e) => {
          if (!last || act !== 'fire') return;
          this.handlers.look(e.clientX - last.x, e.clientY - last.y);
          last.x = e.clientX; last.y = e.clientY;
        });
        const up = () => {
          if (!last) return;
          last = null;
          btn.classList.remove('down');
          this.handlers.action(act, false);
        };
        btn.addEventListener('pointerup', up);
        btn.addEventListener('pointercancel', up);
      });
    },

    releaseSprint() {
      this.sprintLock = false;
      this.move.x = this.move.y = 0;
      $('joy-knob').style.transform = 'translate(0px, 0px)';
      $('joy-sprint').classList.remove('on');
    },

    setEnabled(on) {
      this.enabled = on;
      document.body.classList.toggle('touch-ui', on);
      if (!on) this.releaseSprint();
    },

    // Context button: jump from the plane, open the parachute, or pick up.
    setContext(label) {
      const b = $('t-interact');
      if (b.dataset.label === label) return;
      b.dataset.label = label;
      b.textContent = label;
      b.classList.toggle('hidden', !label);
    },
  };

  ZZ.Touch = Touch;
})();
