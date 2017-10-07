# COP5615 - Project 2

## What is working
* Gossip - Working
* Push-sum - Working

## Largest networks simulated per topology:
* Gossip
  - Full: 8192
  - 2D: 8281
  - Imp2D: 8281
  - Line: 16
* Push-sum
  - Full: 4096
  - 2D: 2116
  - Imp2D: 8281
  - Line: 512

## Implementation notes
Both push-sum and gossip are working and converge. However there are some things to note about the implementation: See [Report.pdf](./report.pdf) for charts visualizing the growth of convergence time as a function of network size.

**Assumptions:**
1. For Gossip, since each node is allowed to re-transmit at periodic intervals I take convergence as the point when over 50% of the gossip network is inactive or less than 1% of the network is active (whichever occurs first)
2. Push-sum's convergence condition is that 50% of the network nodes become inactive. The average of all of these node's computed values is reported as the network average

