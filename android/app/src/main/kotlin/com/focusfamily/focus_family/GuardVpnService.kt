package com.focusfamily.focus_family

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors

/**
 * A local "DNS filter" VPN. Only DNS lookups are routed into this service.
 * Blocked websites get a "not found" answer; everything else is forwarded normally.
 * Nothing is logged or sent to any server.
 */
class GuardVpnService : VpnService() {
    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private val pool = Executors.newFixedThreadPool(6)

    override fun onCreate() {
        super.onCreate()
        RuleStore.load(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (tun == null) start()
        return START_STICKY
    }

    private fun start() {
        try {
            tun = Builder()
                .setSession("FocusFamily website blocking")
                .addAddress("10.0.0.1", 32)
                .addDnsServer(FAKE_DNS)
                .addRoute(FAKE_DNS, 32)
                .setMtu(1500)
                .setBlocking(true)
                .establish()
        } catch (_: Exception) {
            return
        }
        val fd = tun ?: return
        running = true
        worker = Thread { loop(fd) }.also { it.start() }
    }

    private fun loop(fd: ParcelFileDescriptor) {
        val input = FileInputStream(fd.fileDescriptor)
        val output = FileOutputStream(fd.fileDescriptor)
        val buf = ByteArray(32767)
        try {
            while (running) {
                val n = input.read(buf)
                if (n < 0) break
                if (n == 0) continue
                val packet = buf.copyOf(n)
                pool.execute {
                    try {
                        handle(packet, output)
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        } finally {
            running = false
        }
    }

    private fun handle(p: ByteArray, out: FileOutputStream) {
        if (p.size < 28) return
        val version = (p[0].toInt() shr 4) and 0xF
        if (version != 4) return
        val ihl = (p[0].toInt() and 0xF) * 4
        val proto = p[9].toInt() and 0xFF
        if (proto != 17) return // UDP only
        if (p.size < ihl + 8) return
        val dstPort = ((p[ihl + 2].toInt() and 0xFF) shl 8) or (p[ihl + 3].toInt() and 0xFF)
        if (dstPort != 53) return
        val udpLen = ((p[ihl + 4].toInt() and 0xFF) shl 8) or (p[ihl + 5].toInt() and 0xFF)
        val dnsStart = ihl + 8
        val dnsLen = minOf(udpLen - 8, p.size - dnsStart)
        if (dnsLen < 12) return
        val dns = p.copyOfRange(dnsStart, dnsStart + dnsLen)

        val name = parseQName(dns) ?: ""
        val reply: ByteArray? =
            if (name.isNotEmpty() && RuleStore.isDomainBlocked(name)) blockedReply(dns) else forward(dns)
        if (reply == null) return
        val resp = buildPacket(p, ihl, reply)
        synchronized(out) { out.write(resp) }
    }

    private fun parseQName(d: ByteArray): String? {
        var i = 12
        val sb = StringBuilder()
        while (i < d.size) {
            val l = d[i].toInt() and 0xFF
            if (l == 0) break
            if ((l and 0xC0) != 0) return null
            i++
            if (i + l > d.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            sb.append(String(d, i, l, Charsets.US_ASCII))
            i += l
        }
        return sb.toString()
    }

    private fun questionEnd(d: ByteArray): Int {
        var i = 12
        while (i < d.size && d[i].toInt() != 0) i += (d[i].toInt() and 0xFF) + 1
        return minOf(i + 1 + 4, d.size)
    }

    /** DNS answer "this name does not exist" (NXDOMAIN). */
    private fun blockedReply(dns: ByteArray): ByteArray {
        val r = dns.copyOfRange(0, questionEnd(dns))
        r[2] = 0x81.toByte()
        r[3] = 0x83.toByte()
        for (k in 6..11) r[k] = 0
        return r
    }

    private fun forward(dns: ByteArray): ByteArray? {
        for (server in UPSTREAMS) {
            var s: DatagramSocket? = null
            try {
                s = DatagramSocket()
                protect(s) // keep this socket outside the VPN
                s.soTimeout = 3500
                s.send(DatagramPacket(dns, dns.size, InetAddress.getByName(server), 53))
                val rb = ByteArray(4096)
                val rp = DatagramPacket(rb, rb.size)
                s.receive(rp)
                return rb.copyOf(rp.length)
            } catch (_: Exception) {
            } finally {
                s?.close()
            }
        }
        return null
    }

    private fun buildPacket(req: ByteArray, ihl: Int, dns: ByteArray): ByteArray {
        val udpLen = 8 + dns.size
        val total = 20 + udpLen
        val r = ByteArray(total)
        r[0] = 0x45
        r[2] = (total shr 8).toByte()
        r[3] = total.toByte()
        r[8] = 64
        r[9] = 17
        System.arraycopy(req, 16, r, 12, 4) // source = request destination
        System.arraycopy(req, 12, r, 16, 4) // destination = request source
        val cs = checksum(r, 0, 20)
        r[10] = (cs shr 8).toByte()
        r[11] = cs.toByte()
        System.arraycopy(req, ihl + 2, r, 20, 2) // source port = 53
        System.arraycopy(req, ihl, r, 22, 2) // destination port = client port
        r[24] = (udpLen shr 8).toByte()
        r[25] = udpLen.toByte()
        System.arraycopy(dns, 0, r, 28, dns.size)
        return r
    }

    private fun checksum(b: ByteArray, off: Int, len: Int): Int {
        var sum = 0L
        var i = off
        while (i < off + len - 1) {
            sum += (((b[i].toInt() and 0xFF) shl 8) or (b[i + 1].toInt() and 0xFF)).toLong()
            i += 2
        }
        while ((sum shr 16) != 0L) sum = (sum and 0xFFFF) + (sum shr 16)
        return (sum.inv() and 0xFFFF).toInt()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    private fun stopVpn() {
        running = false
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
    }

    companion object {
        @Volatile
        var running = false
        const val FAKE_DNS = "10.0.0.2"
        val UPSTREAMS = listOf("8.8.8.8", "1.1.1.1")
    }
}
