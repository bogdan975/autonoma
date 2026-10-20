import { isPreviewHostname } from "@autonoma/types";
import { env } from "env";

/**
 * The API origin for data-plane calls that must bypass CloudFront: the app
 * host (autonoma.app) sits behind CloudFront, whose WAF/buffering can 403 or
 * mangle request bodies (a large `apply_config` document, a password
 * containing characters that trip injection rules) and interfere with
 * streaming HTTP. `api.<app-host>` is direct to the ALB, off CloudFront.
 * Localhost and per-PR previews reach the API cross-origin at VITE_API_URL.
 * Session cookies and OAuth are unaffected by which origin the data plane
 * uses - crossSubDomainCookies covers both.
 *
 * Self-hosted deployments on any other domain have no `api.<app-host>`, so
 * they also use VITE_API_URL.
 */
export function getApiOrigin(): string {
    const hostname = window.location.hostname;
    const isPreview = isPreviewHostname(hostname, env.VITE_INTERNAL_DOMAIN);
    const isLocalhost = hostname === "localhost";
    const isInternalDomainHost =
        hostname === env.VITE_INTERNAL_DOMAIN || hostname.endsWith(`.${env.VITE_INTERNAL_DOMAIN}`);
    const usesConfiguredApiUrl = isPreview || isLocalhost || !isInternalDomainHost;
    return usesConfiguredApiUrl ? env.VITE_API_URL : `https://api.${hostname}`;
}
