# WhaleChat smart contracts bug bounty

## Rewards

Vulnerability reports will be scored using the  [CVSS v3](https://www.first.org/cvss/) standard. The reward amounts for different types of vulnerabilities are:

- **Critical** (CVSS 9.0 - 10.0): 100 points

- **Major** (CVSS 7.0 - 8.9): 50 points

- **Medium** (CVSS 4.0 - 6.0): 10 points

- **Low** (CVSS 1.0 - 3.9): 5 points

Rewards will be awarded at the sole discretion of the WhaleChat DAO. Quality of the report and reproduction instructions can impact the reward. Rewards will be paid out in `WHALE` tokens.

For this initial bug bounty program, there is a **maximum bounty pool of 1% of all WhaleChat token supply**. The tokens will be distributed to the bounty participants proportionally to their scores.

Example:
```
Participant A: 1 * Major + 1 * Low = 1 * 50 + 1 * 5 = 55 points
Participant B: 2 * Mediums + 3 * Lows = 2 * 10 + 3 * 5 = 35 points

Total points = 55 + 35 = 90 points

Participant A gets 55/90 = 0.61% of tokens
Participant B gets 35/90 = 0.39% of tokens
```

The bug bounty program will run until WhaleChat DAO decides so, starting from the first commit of this document.

## Reporting

- In order to report a vulnerability, please post an issue in GitHub with `[BUG BOUNTY]` in the title.
- We will make our best effort to reply in a timely manner and provide a timeline for resolution.
- Please include a detailed report on the vulnerability with clear reproduction steps. The quality of the report can impact the reward amount.

## Scope

In scope for the bug bounty are all (and only) the smart contracts of WhaleChat, which are in this repository.

## Areas of interest

These are some examples of most important vulnerabilities that must be avoided:

- Steal or lock funds or tokens.
- Freeze or lock the a contract.
- Issue new tickets arbitrarily.
- Buy tickets "for free".

## Out of scope

- Only smart contrats are in the scope. Mobile app and server are out-of-scope for this bounty.
- Exploits as a consequence of wallet security by one or several users.

## Eligibility

- Only unknown vulnerabilities will be awarded a bounty; in case of duplicate reports, the first report will be awarded the bounty.
