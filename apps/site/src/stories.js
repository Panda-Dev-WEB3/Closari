export const chapters = [
  {
    slug: "technology",
    name: "Technology",
    tag: "Pricing",
    deck: "The screen says 62¢. What will a hundred shares cost?",
    alt: "An oscilloscope displays two stepped signals above a coiled coral cable.",
    heading: "The price of the next share",
    intro:
      "On the NVDA paper desk, 62¢ is the price of the next Yes share. Start buying and the quote moves. The slider above traces what happens to that price as a single order grows.",
    notes: [
      [
        "Inventory",
        "How a trade moves the curve",
        "Closari uses a logarithmic market scoring rule, or LMSR, to turn the number of shares sold in each outcome into a price. Buying Yes makes the next Yes share more expensive. In a two-outcome market, No falls by the same amount. The two prices add up to 1 USDG.",
      ],
      [
        "Market depth",
        "Why the budget matters",
        "Before trading opens, the house pool assigns a budget to the market. A larger budget makes the curve flatter. The same purchase then moves the quote less. The budget also sets the most the pool can lose on that market.",
      ],
      [
        "On the ticket",
        "Read the average before you confirm",
        "The ticket adds up the cost of each share along the curve. It shows the average you would pay, the fee and the price the next trader would see. Change the quantity to compare all three.",
      ],
    ],
    link: ["Try the NVDA quote", "/terminal/nvda"],
  },
  {
    slug: "how-it-works",
    name: "What we do",
    tag: "Market formats",
    deck: "Trade a price level, a range, or the move from the open.",
    alt: "A mechanical selector slides between three translucent outcome tabs.",
    heading: "Three ways to read the same close",
    intro:
      "Each trading day, Closari’s design calls for eight markets per stock token. Six ask about individual strikes. The range and up/down markets each ask a different question about the same closing price.",
    notes: [
      [
        "NVDA",
        "Above a strike",
        "Will the NVDA token finish above $190.00? Choose Yes or No. The strike is per token, and the desk shows its equivalent per share alongside it. If the feed’s uncertainty reaches the strike, the market voids.",
      ],
      [
        "TSLA",
        "Inside a range",
        "With a $400 reference, the middle of TSLA’s five intervals runs from $398 up to, but excluding, $402. A clear $399.40 close puts that interval in the money. Each winning share pays 1 USDG.",
      ],
      [
        "SPY",
        "Up from the open",
        "Here the reference is set during the session. The market compares SPY’s recorded 09:30 ET opening price with its close, allowing for uncertainty in both readings. A missing valid open by 11:30 ET voids that up/down market.",
      ],
    ],
    link: ["Browse the 12 instruments", "/markets"],
  },
  {
    slug: "case-study",
    name: "Case study",
    tag: "NVDA trade",
    deck: "Follow 100 NVDA Yes shares from a 62¢ quote to the closing bell.",
    alt: "An open case file holds a price chart and a silicon die.",
    heading: "A 62.72 USDG ticket",
    intro:
      "Take the paper market asking whether NVDA will close above $190.00. Starting at 62¢, a 100-share buy costs 62.41 USDG before fees. The sample’s 0.50% fee adds 0.31 USDG. That puts the entry cost at 62.72 USDG and the next Yes quote at about 62.8¢.",
    notes: [
      [
        "100.00 USDG",
        "A clear close above $190",
        "Each Yes share pays 1 USDG when the close clears the strike and its confidence band. Receiving 100.00 USDG against the 62.72 USDG entry leaves a gain of 37.28 USDG.",
      ],
      [
        "0.00 USDG",
        "A clear close below $190",
        "The No shares pay 1 USDG each. This ticket holds only Yes shares, so it pays zero. The buyer loses the 62.72 USDG paid at entry.",
      ],
      [
        "Variable",
        "A close too near the strike",
        "If the confidence band reaches $190, the market voids. The 100 shares redeem at the time-weighted Yes price over the final hour of trading, or the shorter trading life. The 0.31 USDG fee comes back as well.",
      ],
    ],
    link: ["Open this paper ticket", "/terminal/nvda"],
  },
  {
    slug: "settlement",
    name: "Settlement",
    tag: "Oracle rules",
    deck: "Which price counts when the exchange rings the bell?",
    alt: "A domed exchange bell with a coral plunger.",
    heading: "From the halt to a result",
    intro:
      "A news ticker may show a different close. Closari’s proposed rule starts with a signed Pyth update and applies the token multiplier recorded at listing. The timetable below follows a regular US trading session, in Eastern time.",
    notes: [
      [
        "15:50 ET",
        "Trading stops",
        "Buys and sells close ten minutes before the bell. Positions stay open, and the market keeps the USDG needed to settle them. On an early-close day the halt moves to 12:50 ET.",
      ],
      [
        "16:00 ET",
        "Read the price at the bell",
        "The first regular-session Pyth update in the bell second has priority. If that second has no update, the rule looks back five seconds, then sixty. A submission from a higher-priority window can replace a fallback within 30 minutes. The early-close bell is 13:00 ET.",
      ],
      [
        "Cross-check",
        "Decide whether the price is usable",
        "A Chainlink round from the preceding 15 minutes qualifies for comparison. A difference above 1% voids that stock’s markets for the day. An older round leaves Pyth to govern alone. A Pyth confidence band wider than 0.5% also voids the stock’s markets.",
      ],
      [
        "18:00 ET",
        "The submission window closes",
        "Two hours after the bell, a stock with no usable submitted price voids for the day. Even with a valid price, uncertainty at a strike or a bucket edge can void that particular market. The full rules cover corporate actions and unscheduled closures.",
      ],
    ],
    link: ["Read all settlement rules", "/docs/settlement"],
  },
  {
    slug: "liquidity",
    name: "Liquidity",
    tag: "House pool",
    deck: "Where does the USDG for a winning share come from?",
    alt: "A calibrated reservoir shows the liquid level above its outlet valve.",
    heading: "A budget before the first trade",
    intro:
      "Under the proposed pool design, a market opens with its own USDG. A 2,000 USDG allocation gives the market maker room to quote and limits the pool’s loss on that market to 2,000 USDG. The funds stay with the market through settlement.",
    notes: [
      [
        "Instant exit",
        "Withdraw from free capital",
        "An instant exit draws on USDG the pool has available. Its price already accounts for the least favorable outcome on every open market. A proposed 0.25% exit fee stays in the pool.",
      ],
      [
        "Queued exit",
        "Wait for the day to settle",
        "A queued withdrawal uses the share value after settlement, when the day’s payouts are known and the next markets have yet to trade. This route carries no exit fee.",
      ],
    ],
    closing:
      "Liquidity providers would receive 80% of trading fees and bear market-making losses. Several markets can lose money on the same day, reducing the value of a pool share.",
    link: ["Read the pool example", "/journal/pool"],
  },
  {
    slug: "faq",
    name: "FAQ",
    tag: "Desk guide",
    deck: "Reading a quote, finding a fill, and knowing what happens at the bell.",
    alt: "A mint reference box holds a set of tabbed cards.",
    heading: "Questions at the desk",
    intro:
      "Start with the task in front of you, or search a term from your ticket. The examples use the same paper account and sample session you see in the terminal.",
    notes: [],
    link: ["Open the paper terminal", "/terminal/nvda"],
  },
  {
    slug: "roadmap",
    name: "Roadmap",
    tag: "Engineering plan",
    deck: "What has to work before Closari can settle a live trading day?",
    alt: "A folded contour map traces a coral route between stops.",
    heading: "What counts as ready",
    intro:
      "The paper desk lets you test a quote today. Getting from that quote to a live payout takes eight engineering milestones. Select a milestone for the work it covers and the test it has to pass.",
    notes: [],
    link: ["Inspect the settlement rules", "/docs/settlement"],
  },
].map((chapter, index) => ({
  ...chapter,
  index,
  art: "/chapters/" + chapter.slug + ".webp",
  bannerIcon: "/chapter-icons/" + chapter.slug + ".webp",
  href: "/field/" + chapter.slug,
}));

export const faq = [
  [
    "Can I trade with real funds here?",
    "This is a paper terminal. A fresh account starts with 10,000 paper USDG, and prices come from a fixed sample session. You can review an order, see a fill and track what you hold in this browser.",
    "Using the terminal",
  ],
  [
    "Why does my order cost more than the displayed price?",
    "The displayed price applies to the next share. As you buy, subsequent shares cost a little more. The ticket shows the average for your full order, then adds the fee. Reduce the quantity to see the difference.",
    "Using the terminal",
  ],
  [
    "Where did my positions go?",
    "The terminal saves fills and favorites in this browser for this particular site address. Return to the same address and browser profile to reopen your account. A different port or browser profile starts a separate paper account.",
    "Using the terminal",
  ],
  [
    "Which stocks and funds can I explore?",
    "The desk covers ten companies and two funds. Search NVDA, TSLA, AAPL, AMD, META, MSFT, AMZN, GOOGL, PLTR or MU for a company. SPY and QQQ open the ETF markets. Each instrument has six strikes, one range ladder and one up/down market.",
    "Using the terminal",
  ],
  [
    "Can I sell before the close?",
    "Yes. In the proposed regular session, you can sell shares back to the market maker until trading halts at 15:50 ET. The early-close cutoff is 12:50 ET. The paper desk lets you try a sale against shares you already hold.",
    "Trading and settlement",
  ],
  [
    "What do I receive on a void?",
    "Each share redeems at its outcome’s time-weighted price over the last 60 minutes of trading, or the whole trading life if it was shorter. A guardian void uses the market’s entire trading life. Trading fees paid on that market are refunded. The amount you receive can differ from your original purchase.",
    "Trading and settlement",
  ],
  [
    "What if the closing price lands on a range edge?",
    "If Pyth’s confidence band touches an edge, the whole five-bucket market voids. Otherwise, one interval wins. Each interval includes its lower bound and excludes its upper bound.",
    "Trading and settlement",
  ],
  [
    "Do I need $CLSR to place a trade?",
    "The proposed protocol lets you trade with USDG without holding $CLSR. Staking $CLSR would unlock access features and discounts on the base fee. The late-session surcharge still applies.",
    "Access and fees",
  ],
];

export const roadmap = [
  [
    "M1",
    "Calendar & listings",
    "Set the trading day, its bell time and the instruments eligible for listing. Each market needs the right token multiplier and price feed before it can open.",
    "Run the listing service against holidays, early closes and split dates. Check that it skips ineligible listings and assigns the right bell time to each trading day.",
  ],
  [
    "M2",
    "Market maker",
    "Implement the inventory curve, fees, rounding and trading halt. A quote needs to survive the move from a screen to a signed order.",
    "Compare fills with a high-precision reference and check that the pool’s worst possible loss stays within its budget.",
  ],
  [
    "M3",
    "Settlement",
    "Bind the feed to the market and implement close selection, confidence checks, voids and claims. One submitted update must resolve against the right trading day.",
    "Replay signed prices at the bell and on either side of a boundary. Verify which markets resolve, which void and how much each holder can claim.",
  ],
  [
    "M4",
    "Keeper",
    "The keeper collects signed updates and submits them. A second process needs to finish the job if the first goes offline at the bell.",
    "Stop the primary keeper during a simulated twelve-token session. Its standby must finish settlement, including fallback submissions.",
  ],
  [
    "M5",
    "Indexer & API",
    "Turn contract events into account positions, quotes and settlement records that another application can read.",
    "Replay a chain reorganization and compare API quotes with the contracts. A saved settlement proof must also verify offline.",
  ],
  [
    "M6",
    "Agent tools",
    "Give external tools a way to find a market, request a quote and prepare an order. The user’s signing key stays local.",
    "Run discovery, local signing, submission and a claim on a fork, then reconcile the resulting position.",
  ],
  [
    "M7",
    "Pool & access",
    "Connect deposits, market budgets, withdrawals and fee routing. Add the proposed staking tiers and base-fee discounts.",
    "Test withdrawals while markets hold reserves. Check the fee split and verify when a newly staked balance becomes eligible.",
  ],
  [
    "M8",
    "Replay & review",
    "Replay 30 days of settlement data and put the contracts through external review. These are requirements ahead of a live launch.",
    "Resolve review findings, meet the replay thresholds and complete a dry-run trading day with the proposed 50 USDG test budgets.",
  ],
];
export const articles = [
  [
    "strike",
    "A hundred shares at 62¢",
    "Pricing",
    "How order size changes the price you actually pay.",
    "case-study",
    "A quote machine and order slip on a trading desk.",
  ],
  [
    "range",
    "Five ways a stock can close",
    "Markets",
    "Inside the five buckets of a TSLA range market.",
    "how-it-works",
    "A row of five compartments represents five possible closing ranges.",
  ],
  [
    "open",
    "What counts as the open?",
    "Session",
    "The first valid opening reference determines the up/down comparison.",
    "settlement",
    "A clock and a bell mark the session open.",
  ],
  [
    "oracle",
    "Two feeds at the bell",
    "Settlement",
    "What happens when a fresh cross-check is available, and when it is stale.",
    "settlement",
    "Two receivers sit side by side for a price cross-check.",
  ],
  [
    "pool",
    "The budget behind a quote",
    "Liquidity",
    "How reserved USDG sets the limit for each market.",
    "liquidity",
    "A tank shows the level of the market reserve.",
  ],
  [
    "access",
    "What $CLSR unlocks",
    "Access",
    "The proposed access tiers and fee discounts.",
    "technology",
    "A physical pass slides into an access reader.",
  ],
].map(([slug, title, topic, deck, chapter, alt]) => ({
  alt,
  slug,
  title,
  topic,
  deck,
  chapter,
  art: "/journal/" + slug + ".webp",
}));
