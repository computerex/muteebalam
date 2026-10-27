/* =====================================================================
   muteebalam.com — interactions
   Plain vanilla JS, no dependencies.
   ===================================================================== */
(function () {
  'use strict';

  var root = document.documentElement;
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ── Footer year ────────────────────────────────────────────────── */
  var yearEl = document.getElementById('year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  /* ── Sticky header state ────────────────────────────────────────── */
  var header = document.getElementById('site-header');
  var onScroll = function () {
    if (!header) return;
    header.classList.toggle('is-stuck', window.scrollY > 8);
  };
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  /* ── Mobile navigation ──────────────────────────────────────────── */
  var toggle = document.getElementById('nav-toggle');
  var nav = document.getElementById('primary-nav');

  function setNav(open) {
    if (!toggle || !nav) return;
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
    nav.classList.toggle('is-open', open);
  }

  if (toggle && nav) {
    toggle.addEventListener('click', function () {
      setNav(toggle.getAttribute('aria-expanded') !== 'true');
    });

    nav.addEventListener('click', function (e) {
      if (e.target.closest('a')) setNav(false);
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && nav.classList.contains('is-open')) {
        setNav(false);
        toggle.focus();
      }
    });

    window.addEventListener('resize', function () {
      if (window.innerWidth > 820) setNav(false);
    });
  }

  /* ── Scroll reveal ──────────────────────────────────────────────── */
  var revealTargets = Array.prototype.slice.call(document.querySelectorAll('[data-reveal]'));

  // stagger items inside a shared parent
  revealTargets.forEach(function (el) {
    var siblings = el.parentElement
      ? Array.prototype.filter.call(el.parentElement.children, function (c) {
          return c.hasAttribute('data-reveal');
        })
      : [];
    if (siblings.length > 1) {
      var i = siblings.indexOf(el);
      el.style.setProperty('--d', Math.min(i, 6) * 70 + 'ms');
    }
  });

  if (reduceMotion || !('IntersectionObserver' in window)) {
    revealTargets.forEach(function (el) { el.classList.add('is-visible'); });
  } else {
    var revealedAny = false;

    var revealObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        revealedAny = true;
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -60px 0px', threshold: 0.01 });

    revealTargets.forEach(function (el) { revealObserver.observe(el); });

    // Failsafe: if the observer never delivers anything (unsupported layout
    // context, hidden tab, printing to PDF, etc.) never leave content hidden.
    setTimeout(function () {
      if (revealedAny) return;
      revealTargets.forEach(function (el) { el.classList.add('is-visible'); });
    }, 3000);

    window.addEventListener('beforeprint', function () {
      revealTargets.forEach(function (el) { el.classList.add('is-visible'); });
    });
  }

  /* ── Active section in nav ──────────────────────────────────────── */
  var navLinks = Array.prototype.slice.call(
    document.querySelectorAll('.nav a[href^="#"]:not(.nav-cta)')
  );
  var sections = navLinks
    .map(function (link) {
      var id = link.getAttribute('href').slice(1);
      var el = document.getElementById(id);
      return el ? { link: link, el: el } : null;
    })
    .filter(Boolean);

  if (sections.length && 'IntersectionObserver' in window) {
    var visible = new Map();

    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        visible.set(entry.target.id, entry.isIntersecting ? entry.intersectionRatio : 0);
      });

      var bestId = null;
      var bestRatio = 0;
      visible.forEach(function (ratio, id) {
        if (ratio > bestRatio) { bestRatio = ratio; bestId = id; }
      });

      sections.forEach(function (s) {
        s.link.classList.toggle('is-active', s.el.id === bestId && bestRatio > 0);
      });
    }, { rootMargin: '-45% 0px -45% 0px', threshold: [0, 0.25, 0.6, 1] });

    sections.forEach(function (s) { spy.observe(s.el); });
  }

  /* ── Copy email ─────────────────────────────────────────────────── */
  var copyBtn = document.getElementById('copy-email');
  if (copyBtn) {
    var label = copyBtn.querySelector('.copy-label');
    var original = label ? label.textContent : 'Copy email';
    var resetTimer;

    var flash = function (text, ok) {
      if (!label) return;
      label.textContent = text;
      copyBtn.classList.toggle('is-copied', !!ok);
      clearTimeout(resetTimer);
      resetTimer = setTimeout(function () {
        label.textContent = original;
        copyBtn.classList.remove('is-copied');
      }, 2000);
    };

    copyBtn.addEventListener('click', function () {
      var email = copyBtn.getAttribute('data-email') || '';

      var fallback = function () {
        var ta = document.createElement('textarea');
        ta.value = email;
        ta.setAttribute('readonly', '');
        ta.style.cssText = 'position:fixed;top:-1000px;opacity:0';
        document.body.appendChild(ta);
        ta.select();
        var ok = false;
        try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
        document.body.removeChild(ta);
        flash(ok ? 'Copied!' : 'Copy failed', ok);
      };

      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(email).then(function () {
          flash('Copied!', true);
        }).catch(fallback);
      } else {
        fallback();
      }
    });
  }

  /* ── Certificate lightbox ───────────────────────────────────────── */
  var cards = Array.prototype.slice.call(document.querySelectorAll('.cert-card[data-full]'));
  var lb = document.getElementById('lightbox');

  if (cards.length && lb) {
    var lbImg = document.getElementById('lb-img');
    var lbTitle = document.getElementById('lb-title');
    var lbIssuer = document.getElementById('lb-issuer');
    var lbCounter = document.getElementById('lb-counter');
    var btnPrev = document.getElementById('lb-prev');
    var btnNext = document.getElementById('lb-next');

    var index = 0;
    var lastFocused = null;

    var render = function () {
      var card = cards[index];
      if (!card) return;

      lbImg.src = card.getAttribute('data-full');
      lbImg.alt = card.getAttribute('data-title') + ' certificate';
      lbTitle.textContent = card.getAttribute('data-title') || '';
      lbIssuer.textContent = card.getAttribute('data-issuer') || '';
      lbCounter.textContent = (index + 1) + ' / ' + cards.length;
    };

    var open = function (i) {
      index = i;
      lastFocused = document.activeElement;
      render();

      lb.hidden = false;
      document.body.classList.add('is-locked');

      requestAnimationFrame(function () {
        lb.classList.add('is-open');
        var closeBtn = lb.querySelector('.lightbox-close');
        if (closeBtn) closeBtn.focus();
      });
    };

    var close = function () {
      lb.classList.remove('is-open');
      document.body.classList.remove('is-locked');

      var finish = function () {
        lb.hidden = true;
        lbImg.removeAttribute('src');
        if (lastFocused && lastFocused.focus) lastFocused.focus();
      };

      if (reduceMotion) finish();
      else setTimeout(finish, 260);
    };

    var step = function (dir) {
      index = (index + dir + cards.length) % cards.length;
      render();
    };

    cards.forEach(function (card, i) {
      card.addEventListener('click', function () { open(i); });
    });

    lb.addEventListener('click', function (e) {
      if (e.target.closest('[data-lb-close]')) close();
    });

    if (btnPrev) btnPrev.addEventListener('click', function () { step(-1); });
    if (btnNext) btnNext.addEventListener('click', function () { step(1); });

    document.addEventListener('keydown', function (e) {
      if (lb.hidden) return;

      if (e.key === 'Escape') { e.preventDefault(); close(); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); step(-1); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); step(1); }
      else if (e.key === 'Tab') {
        // keep focus inside the dialog
        var focusables = lb.querySelectorAll('button, [href], img[tabindex]');
        if (!focusables.length) return;
        var first = focusables[0];
        var last = focusables[focusables.length - 1];

        if (e.shiftKey && document.activeElement === first) {
          e.preventDefault(); last.focus();
        } else if (!e.shiftKey && document.activeElement === last) {
          e.preventDefault(); first.focus();
        }
      }
    });

    // swipe between certificates on touch devices
    var touchX = null;
    lb.addEventListener('touchstart', function (e) {
      touchX = e.changedTouches[0].clientX;
    }, { passive: true });

    lb.addEventListener('touchend', function (e) {
      if (touchX === null) return;
      var dx = e.changedTouches[0].clientX - touchX;
      if (Math.abs(dx) > 55) step(dx < 0 ? 1 : -1);
      touchX = null;
    }, { passive: true });
  }
})();
