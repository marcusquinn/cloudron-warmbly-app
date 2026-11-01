// SPDX-License-Identifier: MIT
// SPDX-FileCopyrightText: 2026 Marcus Quinn
//
// Cloudron package addition to the Warmbly dashboard's sign-in screen.
//
// Upstream only offers the OIDC button after an email address has been
// entered, although the address is never used: the Cloudron account decides
// who signs in. This adds "Continue with <provider>" to the first screen and,
// on an instance nobody has claimed yet, says the first sign-in becomes the
// owner. It starts the sign-in exactly as the dashboard does (POST
// /v1/auth/oidc/begin, keep the binding in sessionStorage, go to the provider),
// so the rest of the flow is upstream's own. If the upstream markup changes and
// the email form is not found, it does nothing and the upstream flow remains.
(function () {
	"use strict";

	var MARK = "data-cloudron-sso";
	var BINDING_KEY = "sso_binding"; // web/src/lib/api/client/auth/beginSSO.ts
	var env = window.__WARMBLY_ENV__ || {};
	var api = String(env.API_URL || "").replace(/\/+$/, "");
	var config = null;

	if (!api || !window.fetch || !window.MutationObserver) return;

	function onLoginRoute() {
		return /^\/auth\/(login|register)\/?$/.test(window.location.pathname);
	}

	function emailForm() {
		var input = document.querySelector('form input[type="email"][autocomplete~="webauthn"]');
		return input ? input.closest("form") : null;
	}

	function begin(button, hint) {
		button.disabled = true;
		fetch(api + "/v1/auth/oidc/begin", { method: "POST", headers: { Accept: "application/json" } })
			.then(function (res) {
				if (!res.ok) throw new Error("begin " + res.status);
				return res.json();
			})
			.then(function (data) {
				if (!data || !data.url) throw new Error("no url");
				try { sessionStorage.setItem(BINDING_KEY, data.binding || ""); } catch (e) { /* the exchange will say so */ }
				window.location.href = data.url;
			})
			.catch(function () {
				button.disabled = false;
				hint.textContent = "Couldn't start the sign-in. Try again, or enter your email and choose Continue.";
			});
	}

	function render() {
		if (!config || !onLoginRoute()) return;
		var form = emailForm();
		if (!form || form.parentNode.querySelector("[" + MARK + "]")) return;

		var label = (config.provider_labels && config.provider_labels.oidc) || "Cloudron";
		var block = document.createElement("div");
		block.setAttribute(MARK, "");
		block.className = "space-y-3";

		var divider = document.createElement("div");
		divider.className = "flex items-center gap-3";
		var line1 = document.createElement("div");
		line1.className = "h-px flex-1 bg-slate-200";
		var or = document.createElement("span");
		or.className = "text-[10px] uppercase tracking-[0.14em] text-slate-400";
		or.textContent = "or";
		var line2 = line1.cloneNode();
		divider.appendChild(line1);
		divider.appendChild(or);
		divider.appendChild(line2);

		var button = document.createElement("button");
		button.type = "button";
		button.className = "w-full h-10 rounded-md border border-slate-200 text-[13px] font-medium text-slate-700 hover:bg-slate-50 focus:border-sky-400 focus:ring-2 focus:ring-sky-100 transition-colors disabled:opacity-50";
		button.textContent = "Continue with " + label;

		var hint = document.createElement("p");
		hint.className = "text-center text-[12.5px] text-slate-500";
		hint.textContent = config.cloudron_first_owner
			? "New instance: the first person to sign in with " + label + " becomes its owner and admin. No email or password needed."
			: "Use your " + label + " account. No email or password needed.";

		button.addEventListener("click", function () { begin(button, hint); });

		block.appendChild(divider);
		block.appendChild(button);
		block.appendChild(hint);
		form.parentNode.insertBefore(block, form.nextSibling);
	}

	fetch(api + "/v1/auth/config", { headers: { Accept: "application/json" } })
		.then(function (res) { return res.ok ? res.json() : null; })
		.then(function (data) {
			if (!data || !data.providers || data.providers.indexOf("oidc") < 0) return;
			config = data;
			render();
			new MutationObserver(render).observe(document.body, { childList: true, subtree: true });
		})
		.catch(function () { /* no notice; the upstream flow is unchanged */ });
})();
