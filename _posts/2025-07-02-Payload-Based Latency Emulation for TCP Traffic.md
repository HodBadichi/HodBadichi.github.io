---
layout: post
title: "Payload-Based Latency Emulation for TCP Traffic"
date: 2025-07-02
tags: [networking,latency-emulation,tcp, linux]
excerpt: "Learn how to deliberately create out-of-order packet delivery in TCP traffic using Linux Traffic Control (TC) and iptables. This practical guide shows you how to inspect packet payloads, mark specific packets, and introduce controlled latency to simulate real-world network conditions for testing and analysis."
math: false
---

The internet often feels like magic: your video streams perfectly, and files download flawlessly. But behind the scenes, it's a chaotic place where data packets travel unpredictable paths, arriving out of order or even getting lost entirely.
Yet, TCP works its magic, guaranteeing that if you send 'Boil Water', 'Add Pasta', then 'Drain', the receiver always reconstructs the recipe as needed,no other sequence is possible.

What if you want to peek behind this curtain, perhaps to inspect or modify the mechanisms behind it? How can you deliberately force out-of-order packet delivery in a simple sender-receiver setup?

<img src="/assets/images/2025/7/3/OoO-Example.png" alt="TCP Latency Emulation" width="800">

We can achieve our goal by combining two powerful Linux tools:
- **Traffic Control (TC)**
- **iptables**

This dynamic duo allows you to inspect packet payloads, mark them, and then manipulate their journey with ease.

Here's how we can achieve it:

# Marking the packet

First, we'll use iptables to identify and "mark" the packets we want to delay. Think of this mark as a special flag that TC will recognize later.
Let's break down the iptables command:

```bash
iptables -t mangle -A OUTPUT -m string --string "Pasta" --algo bm -j MARK --set-mark 100
```

- `-t mangle`: We're working within the mangle table, which is designed for altering packet headers and metadata.
- `-A OUTPUT`: This rule is appended to the OUTPUT chain, meaning it will inspect packets originating from our local machine. (You might use `-A FORWARD` for packets being routed through the machine).
- `-m string --string "Pasta" --algo bm`: This is the clever part! We're using the string module to search for a specific substring ("Pasta" in this case) within the packet's payload. The bm algorithm specifies the Boyer-Moore string matching algorithm for efficiency.
- `-j MARK --set-mark 100`: If a packet matches our string, we use the MARK target to assign it a numerical mark of 100. This number is arbitrary; you can choose any value that suits your needs.

# Introducing the latency

With our packets marked, it's time to leverage TC's capabilities, specifically its netem (network emulator) functionality, to introduce the desired delay.

1. **Replacing the Root qdisc:**
   - Before we can add our custom delay, we often need to replace the default qdisc on our network interface. The default mq (multi-queue) qdisc isn't "classful," meaning it doesn't allow us to create different traffic classes that we'll need for our marked packets.

   ```bash
   sudo tc qdisc replace dev eno8303 root handle 1: prio
   ```

   - Here, we're replacing the root qdisc on interface `eno8303` with a priority qdisc, assigned handle `1:`. The prio qdisc allows us to define different bands for traffic.

2. **Setting Up Traffic Bands:**
   - Next, we'll create two child qdiscs under our new root: one for our delayed traffic and another for regular traffic.
     - **Delayed Traffic:** We'll assign the marked packets to this band and introduce latency.

       ```bash
       sudo tc qdisc add dev eno8303 parent 1:1 handle 10: netem delay 100ms
       ```

       - This command adds a netem qdisc to band `1:1` of our root qdisc. We've given it a handle of `10:` and, crucially, set a delay of 100ms.

     - **Regular Traffic:** All other unmarked packets will flow through this band without delay.

       ```bash
       sudo tc qdisc add dev eno8303 parent 1:2 handle 20: fq_codel
       ```

       - Here, we're adding an fq_codel qdisc to band `1:2` with handle `20:`. fq_codel is a fair queueing and congestion avoidance qdisc, suitable for general traffic.

3. **Directing Traffic with Filters:**
   - Finally, we need to tell the root qdisc how to classify incoming packets and send them to the correct band based on our iptables mark.

   ```bash
   sudo tc filter add dev eno8303 protocol ip parent 1: prio 1 handle 100 fw flowid 1:1
   ```

   - This command adds a filter to our prio root qdisc (parent `1:`):
     - `protocol ip`: We're filtering IP packets.
     - `prio 1`: This sets the priority of the filter.
     - `handle 100 fw`: This is the key! We're telling TC to look for packets that have been marked with 100 by iptables.
     - `flowid 1:1`: If a packet matches the fw mark 100, it will be directed to flowid 1:1, which is our netem qdisc responsible for introducing the 100ms delay.

# Putting it to the Test: Seeing the Latency in Action

To confirm our setup works as intended, we need to send some traffic and observe its behavior. We'll use netcat for a simple TCP connection and a small script to send our "Pasta" string.

**Our Test Script (the "Sender"):**

```bash
#!/bin/bash
{
  stdbuf -o0 echo "Boil Water,"
  stdbuf -o0 echo "Add Pasta,"
  stdbuf -o0 echo "Drain"
} | nc -N 10.237.137.20 1234
```

**Setting up the Receiver:**

```bash
nc -l 1234
```

**Observing with tcpdump:**

Initially, you might expect the packets to appear in the order they were sent. However, with our latency rules in place, here's a snippet of what tcpdump reveals:

```text
12:41:03.747945 IP sender-host.example.com.33814 > receiver-host.example.com.1234: Flags [P.], seq 1:13, ack 1, win 502, ... length 12
        0x0030:  ... 426f 696c 2057 6174 6572 2c0a  ..t'Boil.Water,.
12:41:03.751099 IP sender-host.example.com.33814 > receiver-host.example.com.1234: Flags [FP.], seq 24:30, ack 1, win 502, ... length 6
        0x0030:  ... 4472 6169 6e0a                  ..t'Drain.
12:41:03.849006 IP sender-host.example.com.33814 > receiver-host.example.com.1234: Flags [P.], seq 13:24, ack 1, win 502, ... length 11
        0x0030:  ... 4164 6420 5061 7374 612c 0a      ..t'Add.Pasta,.
```

Notice the timestamps! While the "Boil Water" and "Drain" packets arrive relatively quickly, the packet containing "Add Pasta" shows a noticeable delay, appearing later in the tcpdump output despite being sent earlier in the script.

The truly neat part is that despite the reordering observed by tcpdump, the netcat listener on the receiver still displays the output in the correct order:

```
Boil Water,
Add Pasta,
Drain
```

### References

- [tc(8) - Linux manual page](https://man7.org/linux/man-pages/man8/tc.8.html) - Traffic Control utility documentation
- [iptables(8) - Linux manual page](https://linux.die.net/man/8/iptables) - Netfilter firewall administration