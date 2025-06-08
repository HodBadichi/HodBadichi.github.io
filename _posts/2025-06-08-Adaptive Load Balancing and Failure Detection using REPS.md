---
layout: post
title: "Adaptive Load Balancing and Failure Detection using REPS"
date: 2025-06-08
tags: [networking, load-balancing, failure-detection, reps]
excerpt: "Networks need two main things: load balancing and catching problems early. REPS (Recycled Entropy Packet Spraying) is specifically engineered for next-generation out-of-order networks, effectively resolving network failures and optimizing load balancing for intensive AI workloads."
math: false
---
{: .notice--success}

**Paper:** [REPS - Recycled Entropy Packet Spraying for Adaptive Load Balancing and Failure Mitigation](https://arxiv.org/html/2407.21625v3)

# Adaptive Load Balancing and Failure Detection using REPS 

Networks need two main things: load balancing and catching problems early. When networks get busy, all the data might try to use just one path, even when there are many other paths available. This is like having a big highway with many lanes, but everyone crowds into just one lane. In a fat tree topology, two connections might overload one switch when they could have used any other switch instead:

<img src="/assets/images/2025/6/8/fat-tree.png" alt="Fat tree example" width="800">


While previous methods have tackled network load balancing and failure handling, REPS is specifically engineered for the unique demands of "next-generation" out-of-order networks, especially those supporting intensive AI workloads. Its authors developed REPS to effectively resolve network failures and optimize load balancing within this distinct and evolving network environment.

## Load balancing through caching in REPS

REPS achieves load balancing by maintaining a circular buffer that stores Entropy Values (EVs). These EVs represent specific, good-performing network paths. Each path in a connection is identified by an EV, which is embedded in the outgoing packet and guides it through the network.
<img src="/assets/images/2025/6/8/circular_buffer.png" alt="" width="400">

The caching and selection is comprised of two simple steps:

1. Retrieve an EV (path identifier) from the circular buffer's Tail and send packet along that path
2. Upon receiving ACK, evaluate packet success: only EVs from packets without congestion signals (ECN marks) are added back to the circular buffer's Head, maintaining a cache of well-performing paths

Note: When the buffer is empty, an EV is chosen randomly.

How this solves the congestion problem:
Let's use the example of a congested switch in a fat tree network.
When a switch detects congestion, it marks the packet with an ECN. Upon receiving this marked packet, the sender knows that the EV path taken by that packet is currently problematic due to congestion.
Crucially, REPS will not consider this ECN-marked EV as "good-performing." Consequently, it will not add it back into the buffer as a preferred path, or it will eventually be pushed out by other, genuinely good-performing EVs. The next time REPS needs to send a packet, it will automatically select a different, currently "good" EV from its buffer, thereby actively avoiding the congested path.


## Failure mitigation in REPS
When a cable fails, routing systems require time (approximately 10 ms according to the paper) to detect the failure and redirect traffic away from the failed path. During this detection window, packets continue being sent to the broken link and are lost. With typical parameters (4 KiB packets, 400 Gbps link speed), this 10 ms delay results in over 120,000 lost packets - approximately 0.5 GB of data.

REPS addresses this issue through a simple timeout-based failure detection mechanism. When a failure is detected, REPS enters "freeze mode" for a temporary period. During freeze mode, REPS:

1. Stops exploring new EVs (avoiding potentially failed paths)
2. Reuses existing EVs from the circular buffer, even if they may be invalidated

By using freeze mode the authors prioritizes avoiding failed paths immediately when failure is suspected. Even if triggered by mistake (confusing congestion with failure), REPS still maintains good load balancing, making it safe to enter freeze mode conservatively.

## Evaluation

The authors tested REPS using both large simulations and real FPGA hardware to see how well it works in different situations. This graph demonstrates REPS' effectiveness when dealing with an imbalanced network - specifically when one port (shown in green) operates at only 200 Gbps while others run at full 400 Gbps capacity:

<img src="/assets/images/2025/6/8/evaluation-part.png" alt="Evaluation part" width="600">

First lets understand what we're looking at,
this graph compares how well REPS and Oblivious Packet Spraying(OPS) handle port utilization on a switch. Here's what each axis shows:

1. Left Y-axis: Port utilization (how busy the ports are)
2. Right Y-axis: Queue size (how much data is waiting)
3. X-axis: Time

KMin and KMax are the thresholds that trigger congestion control - the system starts managing traffic linearly between these two points.

The key difference is completion time: REPS finishes in about 800ms while OPS takes nearly 1400ms. 

Here's what's happening: OPS is "oblivious" - it doesn't notice that one port is slower (200 Gbps instead of 400 Gbps) and keeps sending data to it at the same rate as the faster ports. This causes the slower port queue to hit the KMin threshold, triggering congestion control that ends up slowing down all the other ports too.

REPS is smarter - it quickly figures out which ports are performing well and uses its EV system to redirect traffic to the faster ports, avoiding the congestion problem entirely. 