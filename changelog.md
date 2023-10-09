

## Version 1
  ### Initial Commit - (Simplified from Velodrome Finance v1 Smart Contracts)

  ### Contract Changes for Kinetix Finance Tokenomics
  1. BribeFactory
     - Internal Bribe part removed
  2. ExternalBribe
     - Unused IGauge interface removed
  3. VeArtProxy
     - tokenURI description changed for Kinetix
  4. Voter
     - Minter,Gauge,Pair and internal bribe parts removed
     - Voting pool structure changed for kinetix tokenomics
     - Code refactored and simplified for just using external bribe 
  5. VotingEscrow
     - Maximum lock time decreased to 1 year
