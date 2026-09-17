# Player guide

## Mode d'emploi en français

Voir [Mode d'emploi joueur](MODE_EMPLOI_JOUEUR.md) pour l'installation,
les commandes, les Pre-Dibs, les debits et les signalements.

## English guide

See [Player Guide](PLAYER_GUIDE_EN.md) for the same player workflow in English.

This guide describes the 0.6.0 release candidate. Live Retail behavior still
requires the final validation listed in [B12 release checklist](../../B12_Release_Candidate_Checklist.md).

## What is a Dib?

A Dib is one seasonal accounting unit assigned by your guild. It is not DKP and it is not a promise that you win an item. Officers configure the season and rank allocations.

## How many Dibs do I have?

Open the player window (`/dibs player`) to see your active-season balance and history. The balance comes from the recorded ledger transactions for that season. A rank change does not rewrite older transactions.

## What does “I Wanna Dibs” do?

It creates a Pre-Dib request for an item when the current season and request policy allow it. The request can be confirmed, cancelled, invalidated, or fulfilled by the workflow. It does not award the item and it does not consume a Dib at request time.

## What happens when an item drops?

RCLootCouncil may show your request and eligibility to officers. RCLootCouncil’s voting/award process decides the winner. Dibs does not automatically choose the player with the highest balance.

## When is a Dib consumed?

Only a qualifying finalized award, or an officer-confirmed historical award with evidence, can create a ledger use. A boss kill, merely receiving an item, or a Vault acquisition does not consume a Dib.

## What can officers see?

Officers can review requests, balances, transaction history, rank-at-transaction evidence, disputes, backups, synchronization status, and (when available) RCLootCouncil award evidence. Player views remain player-scoped.

The Guild Master may disable optional features. A disabled feature can disappear
from navigation, but its stored data is retained and direct or stale access is
rejected. Re-enabling the feature restores access to that data. Core safety
services remain enabled.

See [FAQ](faq.md) for common errors.
