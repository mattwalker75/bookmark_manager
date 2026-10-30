// Example bookmarks for trying the app and for screenshots (BOOKMARKMANAGER_SAMPLE=1 on an empty scratch home).
import Foundation
import BookmarkManagerCore

enum Sample {
    static func library() -> Library {
        let colors = ColorCode.defaults()
        let important = colors[0].id, work = colors[1].id, personal = colors[2].id, reference = colors[3].id
        let admin = Folder(name: "Admin pages", description: "Logins and health pages", bookmarks: [
            Bookmark(name: "Postgres admin", description: "Production database. Be careful.", url: "https://pg.mini.ts.net:8443/browser/", tags: ["database", "admin", "postgres"], colorId: important, hasSecret: true, secret: "user: byowner_admin\npassword: correct-horse-battery\n\nrecovery email: ops@example.com\n\nAPI token (read only):\npgat_7f1c9e2ab4d84f0e9c2a"),
            Bookmark(name: "Router status", url: "http://192.168.1.1/status"),
        ])
        let selfHosted = Folder(name: "Self-hosted apps", description: "The tools running on the Mac mini", folders: [admin], bookmarks: [
            Bookmark(name: "People Manager", description: "A bookmark manager for people. Runs on the Mac mini.", url: "https://people.mini.ts.net", tags: ["people", "contacts"], colorId: work),
            Bookmark(name: "My Business Manager", description: "LLC books, invoices and the Network card.", url: "http://mbm.mini.ts.net:3030", tags: ["llc", "invoices"], hasSecret: true, secret: "login: matt\npassword: example-only"),
            Bookmark(name: "App Router", description: "The launcher with the health lights.", url: "http://router.mini.ts.net", tags: ["launcher"]),
            Bookmark(name: "Junk Tracker", description: "Splurges and weight, phone first.", url: "https://junk.mini.ts.net", tags: ["health"], colorId: personal),
        ])
        let vendors = Folder(name: "Vendors", description: "Accounts we pay for", bookmarks: [
            Bookmark(name: "Webull", description: "Brokerage. Sandbox keys live in the Trading Desk.", url: "https://www.webull.com", tags: ["broker", "trading"], colorId: important, hasSecret: true, secret: "account: 0000-0000\npin: 0000"),
            Bookmark(name: "Namecheap", description: "Domains and DNS.", url: "https://www.namecheap.com", tags: ["dns", "domains"], hasSecret: true, secret: "user: example\n2FA: authenticator app"),
            Bookmark(name: "AWS console", url: "https://console.aws.amazon.com", tags: ["cloud", "s3"], hasSecret: true, secret: "account alias: example\nIAM user: matt"),
        ])
        let reading = Folder(name: "Reading", bookmarks: [
            Bookmark(name: "Human Interface Guidelines", url: "https://developer.apple.com/design/human-interface-guidelines", tags: ["apple", "design"], colorId: reference),
            Bookmark(name: "Swift forums", url: "https://forums.swift.org", tags: ["swift"]),
        ])
        let workTab = Folder(name: "Work", folders: [selfHosted, vendors, reading], bookmarks: [
            Bookmark(name: "Mac mini dashboard", url: "http://mini.local:8080"),
            Bookmark(name: "Tailscale admin", description: "Machines, keys and the DNS name for each tool.", url: "https://login.tailscale.com/admin", tags: ["network", "vpn"], colorId: work, hasSecret: true, secret: "auth key (expires yearly): tskey-example"),
            Bookmark(name: "Wi-Fi password", description: "Guest network and the admin password.", url: "", tags: ["wifi"], hasSecret: true, secret: "guest: MintyFresh-2026\nadmin: example-only"),
            Bookmark(name: "Backup passphrase", url: "", tags: ["restic", "backup"], colorId: important, hasSecret: true, secret: "restic repository: sftp:backup@mini:/srv/restic\nrepository password: correct-horse-battery-staple-91\n\nrecovery words (24):\n 1. ladder    2. velvet    3. orbit     4. canyon\n 5. mango     6. thunder   7. pixel     8. harbor\n 9. walnut   10. comet    11. fossil   12. lantern\n13. marble   14. saddle   15. tundra   16. violin\n17. anchor   18. nectar   19. quartz   20. ribbon\n21. summit   22. tiger    23. umbrella 24. zephyr\n\nTime Machine disk password:\nTM-9f3a-kelp-2c7e\n\nOff-site copy (Backblaze B2):\nkeyID: 0045a1b2c3d4e5f0000000003\napplicationKey: K004-example-only\nbucket: mini-offsite-2026\n\nEncrypted DMG (old laptop):\nPhotos-2019.dmg → \"sierra nevada 1987\""),
        ])
        let homeTab = Folder(name: "Home", folders: [
            Folder(name: "Network", description: "The home network", bookmarks: [
                Bookmark(name: "UniFi controller", url: "https://unifi.local", tags: ["admin", "network"]),
                Bookmark(name: "Router admin page", url: "http://192.168.1.1", tags: ["network"]),
            ]),
            Folder(name: "Recipes", bookmarks: [Bookmark(name: "Serious Eats", url: "https://www.seriouseats.com", colorId: personal)]),
        ])
        let devTab = Folder(name: "Dev", folders: [
            Folder(name: "GitHub", bookmarks: [
                Bookmark(name: "GitHub organization settings", url: "https://github.com/organizations/example/settings/admin", colorId: reference),
                Bookmark(name: "Pull requests", url: "https://github.com/pulls"),
            ]),
        ], bookmarks: [Bookmark(name: "Swift Package Index", url: "https://swiftpackageindex.com", tags: ["swift", "packages"])])
        let financeTab = Folder(name: "Finance", bookmarks: [Bookmark(name: "Bank", url: "https://www.example-bank.com", colorId: important, hasSecret: true, secret: "user: example")])
        return Library(colors: colors, tabs: [workTab, homeTab, devTab, financeTab])
    }
}
