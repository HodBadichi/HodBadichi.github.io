---
layout: single
title: "Understanding Memory Level Parallelism Through Binary Search"
date: 2025-06-01
tags: [cpu-architecture, performance, memory, hardware]
excerpt: "Beyond binary search's $O(log n)$ complexity lies a story of CPU optimization. Modern processors don't wait for memory they predict, prefetch, and parallelize memory operations, turning what seems like a simple algorithm into a showcase of memory level parallelism."
math: true
---
{: .notice--success}

**Code:** You can find the code used for this analysis in the following GitHub repository: [Posts-Code/19122024](https://github.com/HodBadichi/Posts-Code/tree/main/19122024)

Beyond binary search's $O(log n)$ complexity lies a story of CPU optimization. Modern processors don't wait for memory they predict, prefetch, and parallelize memory operations, turning what seems like a simple algorithm into a showcase of memory level parallelism.

Let's start with a standard binary search implementation:

```cpp
int binary_search(int* arr, int size, int target) {
    int left = 0;
    int right = size - 1;
    
    while (left <= right) {
        int mid = left + (right - left) / 2;
        if (arr[mid] == target) return mid;
        if (arr[mid] < target) left = mid + 1;
        else right = mid - 1;
    }
    return -1;
}
```

We'll use an array big enough to exceed our caches of $3.73$[GB] ($100$[m] integers) and perform $10$[m] lookups. Using Intel TMA (Top-down Microarchitecture Analysis), we can see the performance bottlenecks:

```
    74,870,673,648      TOPDOWN.SLOTS                    #     20.1 %  tma_backend_bound      
                                                  #     42.7 %  tma_bad_speculation    
                                                  #     33.7 %  tma_frontend_bound     
                                                  #      3.5 %  tma_retiring  
```

Only 20% of the time is spent on backend operations (including memory stalls). The majority of time (42.7%) is spent on bad speculation, which makes sense given the 50/50 branch prediction scenario in binary search.

## Measuring Memory Level Parallelism

Unlike other performance metrics, MLP cannot be directly measured through PMU counters. Instead, best practices typically rely on either full-system simulators or analytical/partial modeling approaches to quantify MLP characteristics. 

One practical approach to estimate average MLP is through the following perf events:
- `l1d_pend_miss.pending`: Total number of pending L1 data cache misses
- `l1d_pend_miss.pending_cycles`: Total cycles with pending L1 data cache misses

These metrics allow us to calculate the average MLP specifically for L1 data cache misses, which provides insight into how effectively our code utilizes memory-level parallelism at the L1 cache level:

$$
MLP_{avg} = \frac{l1d\_pend\_miss.pending}{l1d\_pend\_miss.pending} 
$$

The calculated $MLP_{avg}$ represents the average number of concurrent L1 cache misses. This value is fundamentally limited by the number of MSHRs available in the L1 data cache, which determines how many outstanding cache misses the processor can track simultaneously.
  
Analyzing our binary search implementation yields the following metrics:
```
    98,278,263,019      l1d_pend_miss.pending

    11,219,972,459      l1d_pend_miss.pending_cycles 
```

Calculating the average MLP:

$MLP_{avg} = \frac{98,278,263,019}{11,219,972,459} \approx 8.8$

This result highlights a crucial aspect of modern CPU performance analysis: while our binary search algorithm appears to be inherently serial, the actual MLP measurement shows significant parallelism. This discrepancy occurs because modern CPUs employ speculation techniques that can overlap memory operations, even in seemingly sequential code. 

The observed MLP of 8.76 is significantly higher than the expected value of 1, which can be explained by two types of out-of-order execution:

1. Function-level overlap: The CPU can execute multiple `binary_search()` calls concurrently, as these are independent operations that don't require speculation.

2. Iteration-level overlap: Within a single `binary_search()` call, the CPU overlap memory operations across different iterations.

The key distinction is that function-level overlap is deterministic (the CPU knows these operations are independent), while iteration-level overlap requires speculation (the CPU must predict which path the binary search will take).

To measure the impact of function-level overlap, we can use the `rdtscp` instruction as a serialization barrier, forcing the CPU to complete one query before starting the next. Running our benchmark with this modification yields:

```
    109,103,656,601      l1d_pend_miss.pending                                                 
     13,004,667,591      l1d_pend_miss.pending_cycles   
```

Calculating the MLP for this version:
$$MLP_{avg} = \frac{109,103,656,601}{13,004,667,591} \approx 8.39$$

This result is particularly interesting: despite using a serialization barrier, the MLP only decreased by about 5% from our original measurement of 8.76. This suggests that function-level overlap contributes less to our observed MLP than we might have expected, indicating that most of the parallelism comes from iteration-level overlap within each binary search operation.


Running a branchless version we will be able to verify the MLP indeed comes from speculation:
```cpp
int binary_search_branchless(const int arr[], int size, int target) {
    int *base = const_cast<int*>(arr);
    int len = size;
    
    while (len > 1) {
        int half = len / 2;
        base += (base[half - 1] < target) * half;
        len -= half;
    }
    
    return (base - arr);
}
```

and indeed we get  MLP of 1.
```
    14,443,856,192      l1d_pend_miss.pending                                                 
    14,418,507,045      l1d_pend_miss.pending_cycles  
```

### MLP limitations

MLP is constrained by two main factors:

1. Hardware limitations:
   - Reorder Buffer (ROB) size: Determines how many instructions can be in-flight
   - Number of MSHRs (Miss Status Holding Registers): Limits concurrent cache misses

2. Program characteristics:
   - Load clustering: How memory accesses are distributed
   - Out-of-order opportunities: Sequential dependencies (like pointer chasing) limit parallel execution
   - Speculation opportunities: Whether the code allows for effective branch prediction

In our binary search example, we observed an MLP of 8. This value reveals several insights:
- The MSHR limit isn't the bottleneck (Intel Sapphire Rapids supports 16 MSHRs)
- The observed MLP of 8 suggests the limiting factors are:
  - ROB size constraints
  - Limited speculation depth beyond L1 cache

Honestly, without a detailed microarchitecture simulator, it's pretty hard to say exactly why our MLP isn't maxing out the MSHRs. A full-on simulator would probably be able to figure it out, though.