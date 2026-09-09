local Dns = require("booxbook.doh")

package.loaded.json = {
    decode = function()
        return { Status = 0, Answer = {
            { type = 1, data = "104.21.1.2", TTL = 120 },
            { type = 28, data = "2001:db8::1", TTL = 10 },
            { type = 1, data = "999.1.1.1", TTL = 10 },
            { type = 1, data = "172.67.3.4", TTL = 300 },
        } }
    end,
}

local addresses, expires = Dns.parse("response", 1000)
assert(#addresses == 2 and addresses[1] == "104.21.1.2" and addresses[2] == "172.67.3.4",
    "DoH keeps valid IPv4 answers")
assert(expires == 1120, "DoH cache honors the shortest valid TTL")

package.loaded.json = { decode = function() return { Status = 3 } end }
assert(Dns.parse("response") == nil, "DoH rejects failed DNS responses")
package.loaded.json = { decode = function() return { Status = 0, Answer = "invalid" } end }
assert(Dns.parse("response") == nil, "DoH rejects malformed answer lists")

local cert = { extensions = function() return {
    { dNSName = { "graph.microsoft.com", "*.files.1drv.com" } },
} end }
assert(Dns.certificateMatchesHost(cert, "graph.microsoft.com"), "exact SAN matches")
assert(Dns.certificateMatchesHost(cert, "download.files.1drv.com"), "one-label wildcard SAN matches")
assert(not Dns.certificateMatchesHost(cert, "deep.download.files.1drv.com"), "wildcard spans one label only")
assert(not Dns.certificateMatchesHost(cert, "evil.example"), "foreign SAN is rejected")
assert(not Dns.certificateMatchesHost({ extensions = function() return {} end }, "graph.microsoft.com"),
    "missing SAN fails closed")
package.loaded.json = nil
print("DoH response checks passed")
