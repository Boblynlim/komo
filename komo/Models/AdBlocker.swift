import Foundation
import KomoCEF

/// A lightweight, built-in ad/tracker blocklist. Hosts matching (or subdomains
/// of) these domains are cancelled by the engine before they hit the network
/// (see KomoCEF's OnBeforeResourceLoad). Conservative on purpose — well-known
/// ad/analytics/attribution domains only, so it doesn't break page content.
enum AdBlocker {
    static let blockedDomains: [String] = [
        // Google ads & analytics
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adservice.google.com", "2mdn.net", "app-measurement.com",
        // Ad exchanges / SSPs
        "adnxs.com", "rubiconproject.com", "pubmatic.com", "openx.net",
        "casalemedia.com", "criteo.com", "criteo.net", "adsrvr.org",
        "rlcdn.com", "serving-sys.com", "3lift.com", "sharethrough.com",
        "smartadserver.com", "yieldmo.com", "bidswitch.net", "gumgum.com",
        "contextweb.com", "districtm.io", "yieldlab.net",
        // Content recommendation / native ads
        "taboola.com", "outbrain.com", "revcontent.com", "mgid.com",
        // Social ad trackers
        "ads-twitter.com", "analytics.tiktok.com", "ads.tiktok.com",
        "ads.pinterest.com", "ads.linkedin.com",
        // Analytics / session replay
        "scorecardresearch.com", "quantserve.com", "quantcount.com",
        "hotjar.com", "mixpanel.com", "segment.com", "segment.io",
        "amplitude.com", "fullstory.com", "mouseflow.com", "crazyegg.com",
        "chartbeat.com", "parsely.com",
        // Attribution / mobile
        "appsflyer.com", "adjust.com", "kochava.com", "branch.io",
        // Adobe / Oracle / data brokers
        "demdex.net", "everesttech.net", "omtrdc.net", "bluekai.com",
        "krxd.net", "agkn.com", "adsymptotic.com",
        // Amazon ads
        "amazon-adsystem.com",
        // Misc verification / trackers
        "moatads.com", "doubleverify.com", "adsafeprotected.com",
        "zedo.com", "sizmek.com",
    ]

    /// Push the blocklist into the engine. Call once after CEF init.
    static func install() {
        let cStrings = blockedDomains.map { strdup($0) }
        let pointers = cStrings.map { UnsafePointer($0) }
        pointers.withUnsafeBufferPointer { buf in
            komo_cef_set_blocklist(buf.baseAddress, Int32(buf.count))
        }
        cStrings.forEach { free($0) }
    }
}
