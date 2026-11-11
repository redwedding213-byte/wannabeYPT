// wannabeYPT — Discord Activities (Embedded App SDK) bridge
// Copyright (C) 2026 redwedding
//
// This file is part of wannabeYPT. This program is free software: you can
// redistribute it and/or modify it under the terms of the GNU Affero General
// Public License as published by the Free Software Foundation, version 3.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

// Talks to Discord through the official Embedded App SDK
// (@discord/embedded-app-sdk, vendored under ./discord-sdk/) when this
// page is running inside a Discord Activity iframe. In a normal browser
// tab it does nothing at all: the SDK is never even fetched.
//
// Why Activities and not the old local RPC WebSocket: Discord removed
// RPC Origin registration from the Developer Portal, so a website can
// no longer allowlist its origin and the local RPC server disconnects
// every web connection instantly. Activities are Discord's current,
// supported route for web apps: the site runs in an iframe inside
// Discord (served through <app-id>.discordsays.com) and the SDK talks
// to the Discord client over postMessage.
//
// Auth flow (per docs.discord.com, Embedded App SDK):
//   ready() -> authorize({scope: identify + rpc.activities.write},
//   PKCE code_challenge) -> code -> POST the code + code_verifier to
//   https://discord.com/api/oauth2/token (Discord's token endpoint
//   allows cross-origin requests) -> access_token ->
//   authenticate({access_token}) -> setActivity().
// No backend and no client_secret are involved: the exchange uses
// PKCE, which is designed for public clients. That needs two portal
// settings on the Discord application or the exchange fails silently:
//   1. OAuth2 -> "Public Client" switched ON.
//   2. OAuth2 -> Redirects contains https://127.0.0.1.
// The access token lives in memory only (never localStorage) and is
// re-issued on the next page load; authorize() is silent when the
// user has already approved the app, and shows Discord's approval
// modal the first time.
//
// Everything here fails silently: not in Discord, SDK load failure,
// user denies the modal, token exchange rejected, setActivity
// rejected (e.g. rpc.activities.write not approved for the app) —
// every path returns false, never throws, never shows UI.
(function () {
  'use strict';

  var CLIENT_ID = '1570010774070362212';
  var TOKEN_URL = 'https://discord.com/api/oauth2/token';
  var REDIRECT_URI = 'https://127.0.0.1';
  var READY_TIMEOUT_MS = 5000;

  var sdk = null;
  var readyPromise = null;
  var authPromise = null;
  var accessToken = null;

  // True only when this page is the wannabeYPT Activity running inside
  // Discord: Discord serves the Activity from <app-id>.discordsays.com
  // and appends frame_id + instance_id query params. A plain browser
  // tab (even one iframed elsewhere) fails this check.
  function isActivity() {
    try {
      if (typeof window === 'undefined') return false;
      if (window.self === window.top) return false;
      var host = (window.location && window.location.hostname) || '';
      if (host.slice(-15) === '.discordsays.com') return true;
      var q = new URLSearchParams(window.location.search || '');
      return q.has('frame_id') && q.has('instance_id');
    } catch (e) {
      return false;
    }
  }

  // -- PKCE (RFC 7636) -------------------------------------------------

  function b64url(bytes) {
    var bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  // 32 random bytes -> 43-char base64url string (no padding).
  function randomVerifier() {
    var bytes = new Uint8Array(32);
    window.crypto.getRandomValues(bytes);
    return b64url(bytes);
  }

  // base64url(SHA-256(verifier)).
  function challengeFor(verifier) {
    var data = new TextEncoder().encode(verifier);
    return window.crypto.subtle.digest('SHA-256', data).then(function (hash) {
      return b64url(new Uint8Array(hash));
    });
  }

  // -- SDK lifecycle ----------------------------------------------------

  // Lazily load the vendored SDK and handshake with the Discord client.
  // Resolves true only inside a real Activity; false everywhere else.
  // A failed attempt is forgotten so a later study start can retry.
  function init() {
    if (sdk) return Promise.resolve(true);
    if (!isActivity()) return Promise.resolve(false);
    if (!readyPromise) {
      readyPromise = (async function () {
        try {
          var mod = await import('./discord-sdk/index.mjs');
          var s = new mod.DiscordSDK(CLIENT_ID);
          await Promise.race([
            s.ready(),
            new Promise(function (_, reject) {
              setTimeout(function () {
                reject(new Error('discord ready timeout'));
              }, READY_TIMEOUT_MS);
            }),
          ]);
          sdk = s;
          return true;
        } catch (e) {
          return false;
        }
      })();
      readyPromise = readyPromise.then(function (ok) {
        if (!ok) readyPromise = null;
        return ok;
      });
    }
    return readyPromise;
  }

  // Full auth: authorize (PKCE) -> exchange code for a token in the
  // browser -> authenticate the SDK session. The token is kept in
  // memory only. A failed attempt is forgotten so the next study
  // start can retry (e.g. after the user approves the modal).
  function ensureAuth() {
    if (accessToken) return Promise.resolve(true);
    if (authPromise) return authPromise;
    authPromise = (async function () {
      try {
        var ok = await init();
        if (!ok) return false;
        var verifier = randomVerifier();
        var challenge = await challengeFor(verifier);
        // No `prompt`: Discord shows its approval modal only the first
        // time; afterwards it returns a code silently.
        var res = await sdk.commands.authorize({
          client_id: CLIENT_ID,
          response_type: 'code',
          scope: ['identify', 'rpc.activities.write'],
          code_challenge: challenge,
          code_challenge_method: 'S256',
        });
        var code = res && res.code;
        if (!code) return false;
        var body = new URLSearchParams();
        body.set('client_id', CLIENT_ID);
        body.set('grant_type', 'authorization_code');
        body.set('code', code);
        body.set('redirect_uri', REDIRECT_URI);
        body.set('code_verifier', verifier);
        var r = await fetch(TOKEN_URL, {
          method: 'POST',
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body.toString(),
        });
        if (!r.ok) return false;
        var j = await r.json();
        if (!j || !j.access_token) return false;
        await sdk.commands.authenticate({access_token: j.access_token});
        accessToken = j.access_token;
        return true;
      } catch (e) {
        return false;
      }
    })();
    return authPromise.then(function (result) {
      if (!result) authPromise = null;
      return result;
    });
  }

  // -- Presence ---------------------------------------------------------

  // Show "Studying <subject>" with an elapsed timer. Returns true only
  // when Discord accepted the update.
  function setActivity(details, state, startedAtMs) {
    return ensureAuth()
      .then(function (ok) {
        if (!ok || !sdk) return false;
        return sdk.commands
          .setActivity({
            activity: {
              type: 0,
              details: details,
              state: state,
              timestamps: {start: startedAtMs},
            },
          })
          .then(function () {
            return true;
          })
          .catch(function () {
            return false;
          });
      })
      .catch(function () {
        return false;
      });
  }

  // Clear the presence. No-op (false) when never authed.
  function clearActivity() {
    if (!sdk || !accessToken) return Promise.resolve(false);
    return sdk.commands
      .setActivity({activity: null})
      .then(function () {
        return true;
      })
      .catch(function () {
        return false;
      });
  }

  window.wannabeDiscord = {
    isActivity: isActivity,
    init: init,
    setActivity: setActivity,
    clearActivity: clearActivity,
    // Exposed for tests only (PKCE math is verified against RFC 7636).
    _pkce: {randomVerifier: randomVerifier, challengeFor: challengeFor},
  };
})();
