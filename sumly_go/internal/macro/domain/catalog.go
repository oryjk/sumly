package domain

const (
	SectionTreasuryFiscal  = "treasury_fiscal"
	SectionOpportunityCost = "opportunity_cost"
	SectionDollarLiquidity = "dollar_liquidity"
	SectionInflationGrowth = "inflation_growth"
	SectionOfficialMarket  = "official_market"
	SectionRiskTemperature = "risk_temperature"
)

const (
	SourceTreasury = "treasury"
	SourceFRED     = "fred"
	SourceYahoo    = "yahoo"
	SourceSPDR     = "spdr"
	SourceCFTC     = "cftc"
	SourceBitcoin  = "bitcoin"
	SourceIMF      = "imf"
	SourceSeedCSV  = "seedcsv"
	SourceDerived  = "derived"
)

const (
	SeriesUSDebtDaily         = "US_DEBT_DAILY"
	SeriesDFII10              = "DFII10"
	SeriesDFII5               = "DFII5"
	SeriesT10YIE              = "T10YIE"
	SeriesDGS10               = "DGS10"
	SeriesDGS2                = "DGS2"
	SeriesTreasury10Y2YSpread = "TREASURY_10Y_2Y_SPREAD"
	SeriesFEDFUNDS            = "FEDFUNDS"
	SeriesDTWEXBGS            = "DTWEXBGS"
	SeriesDEXCHUS             = "DEXCHUS"
	SeriesNFCI                = "NFCI"
	SeriesPCEPILFE            = "PCEPILFE"
	SeriesCPIAUCSL            = "CPIAUCSL"
	SeriesIPMAN               = "IPMAN"
	SeriesUNRATE              = "UNRATE"
	SeriesFYFSGDA188S         = "FYFSGDA188S"
	SeriesGFDEBTN             = "GFDEBTN"
	SeriesGFDEGDQ188S         = "GFDEGDQ188S"
	SeriesFYOINT              = "FYOINT"
	SeriesFYFR                = "FYFR"
	SeriesWALCL               = "WALCL"
	SeriesGVZCLS              = "GVZCLS"
	SeriesGoldUSD             = "GOLDAMGBD228NLBM"
	SeriesSilver              = "SILVER"
	SeriesOil                 = "OIL"
	SeriesSPY                 = "SPY"
	SeriesQQQ                 = "QQQ"
	SeriesTLT                 = "TLT"
	SeriesIEF                 = "IEF"
	SeriesSHV                 = "SHV"
	SeriesXAU                 = "XAU"
	SeriesHUI                 = "HUI"
	SeriesGLD                 = "GLD"
	SeriesGLDPrice            = "GLD_PRICE"
	SeriesGoldCOT             = "GOLD_COT"
	SeriesBTCUSD              = "BTC_USD"
	SeriesBTCMCap             = "BTC_MCAP"
	SeriesUSDReserveShare     = "USD_RESERVE_SHARE"
	SeriesCBGoldNet           = "CB_GOLD_NET"
	SeriesPCEYoY              = "PCE_YOY"
	SeriesInterestRatio       = "INTEREST_RATIO"
	SeriesFiscalStress        = "FISCAL_STRESS"
	SeriesGoldMA              = "GOLD_MA"
	SeriesGoldCNY             = "GOLD_CNY"
	SeriesShanghaiPremium     = "SHANGHAI_PREMIUM"
	SeriesGoldSilverRatio     = "GOLD_SILVER_RATIO"
	SeriesGoldOilRatio        = "GOLD_OIL_RATIO"
)

var defaultSections = []SectionMeta{
	{
		ID:           SectionTreasuryFiscal,
		NameZh:       "美债与财政信用",
		Description:  "美国国债规模、财政赤字、付息负担、联储资产负债表与央行购金等长期信用逻辑",
		DisplayOrder: 1,
	},
	{
		ID:           SectionOpportunityCost,
		NameZh:       "利率与机会成本",
		Description:  "实际收益率、名义美债收益率、期限利差与股债机会成本变化",
		DisplayOrder: 2,
	},
	{
		ID:           SectionDollarLiquidity,
		NameZh:       "美元与流动性",
		Description:  "广义美元指数、人民币汇率与金融条件松紧对金价的影响",
		DisplayOrder: 3,
	},
	{
		ID:           SectionInflationGrowth,
		NameZh:       "通胀与增长",
		Description:  "核心 PCE、CPI 通胀粘性与制造业、就业周期",
		DisplayOrder: 4,
	},
	{
		ID:           SectionOfficialMarket,
		NameZh:       "贵金属与跨资产",
		Description:  "国际金价、人民币金价、上海金溢价、白银原油比价与金矿股指数",
		DisplayOrder: 5,
	},
	{
		ID:           SectionRiskTemperature,
		NameZh:       "资金情绪与波动",
		Description:  "黄金隐含波动率、SPDR ETF 持仓、CFTC 投机头寸、比特币与均线动量",
		DisplayOrder: 6,
	},
}

var defaultCatalog = []SeriesMeta{
	// 1. treasury_fiscal
	{
		SeriesID:     SeriesUSDebtDaily,
		NameZh:       "美国国债总规模（日频）",
		Section:      SectionTreasuryFiscal,
		Unit:         "trillion_usd",
		Frequency:    "daily",
		Source:       SourceTreasury,
		GoldRelation: "positive",
		PlainNote:    "美国财政部每日公布的联邦公共债务总额；债务持续膨胀长期稀释法币信用，支撑黄金配置价值。",
		DisplayOrder: 1,
	},
	{
		SeriesID:     SeriesGFDEBTN,
		NameZh:       "美国国债总规模（季频）",
		Section:      SectionTreasuryFiscal,
		Unit:         "trillion_usd",
		Frequency:    "quarterly",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "FRED 季频联邦总债务，与日频美债口径统一为万亿美元，用于长周期趋势观察。",
		DisplayOrder: 2,
	},
	{
		SeriesID:     SeriesGFDEGDQ188S,
		NameZh:       "联邦债务 / GDP",
		Section:      SectionTreasuryFiscal,
		Unit:         "percent",
		Frequency:    "quarterly",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "美国联邦债务占名义 GDP 比重；高于 100% 且持续攀升时，市场对美元长期信用的担忧升温。",
		DisplayOrder: 3,
	},
	{
		SeriesID:     SeriesFYFSGDA188S,
		NameZh:       "财政赤字 / GDP",
		Section:      SectionTreasuryFiscal,
		Unit:         "percent",
		Frequency:    "annual",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "美国联邦财政盈余/赤字占 GDP 比例（负值代表赤字）；长期大额赤字是金价结构性顺风。",
		DisplayOrder: 4,
	},
	{
		SeriesID:     SeriesFYOINT,
		NameZh:       "联邦政府付息支出",
		Section:      SectionTreasuryFiscal,
		Unit:         "million_usd",
		Frequency:    "annual",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "美国财政年度债务利息支出；高利率叠加大债务会推升付息压力。",
		DisplayOrder: 5,
	},
	{
		SeriesID:     SeriesFYFR,
		NameZh:       "联邦政府财政收入",
		Section:      SectionTreasuryFiscal,
		Unit:         "million_usd",
		Frequency:    "annual",
		Source:       SourceFRED,
		GoldRelation: "neutral",
		PlainNote:    "美国联邦政府年度税收与财政总收入，用来衡量偿债与付息承载能力。",
		DisplayOrder: 6,
	},
	{
		SeriesID:     SeriesInterestRatio,
		NameZh:       "付息支出占财政收入比",
		Section:      SectionTreasuryFiscal,
		Unit:         "percent",
		Frequency:    "annual",
		Source:       SourceDerived,
		GoldRelation: "positive",
		PlainNote:    "利息支出 / 财政收入；突破 15% 后财政空间明显收窄，强化黄金的避险与去信用属性。",
		DisplayOrder: 7,
	},
	{
		SeriesID:     SeriesFiscalStress,
		NameZh:       "美国财政压力指数",
		Section:      SectionTreasuryFiscal,
		Unit:         "index",
		Frequency:    "annual",
		Source:       SourceDerived,
		GoldRelation: "positive",
		PlainNote:    "综合付息占比、赤字率与债务率的非线性压力评分（0-100），分值越高代表长期黄金顺风越强。",
		DisplayOrder: 8,
	},
	{
		SeriesID:     SeriesWALCL,
		NameZh:       "美联储资产负债表总规模",
		Section:      SectionTreasuryFiscal,
		Unit:         "billion_usd",
		Frequency:    "weekly",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "美联储总资产规模（十亿美元）；扩表释放流动性通常利好黄金，缩表则构成边际压制。",
		DisplayOrder: 9,
	},
	{
		SeriesID:     SeriesCBGoldNet,
		NameZh:       "全球央行净购金",
		Section:      SectionTreasuryFiscal,
		Unit:         "tons",
		Frequency:    "annual",
		Source:       SourceSeedCSV,
		GoldRelation: "positive",
		PlainNote:    "世界黄金协会统计的全球央行年度净购金量；央行持续大手笔买金为金价提供坚实底部买盘。",
		DisplayOrder: 10,
	},
	{
		SeriesID:     SeriesUSDReserveShare,
		NameZh:       "美元全球外储占比",
		Section:      SectionTreasuryFiscal,
		Unit:         "percent",
		Frequency:    "quarterly",
		Source:       SourceIMF,
		GoldRelation: "negative",
		PlainNote:    "IMF COFER 美元在全球已分配外汇储备中的份额；占比趋势性下行利好黄金替代储备需求。",
		DisplayOrder: 11,
	},

	// 2. opportunity_cost
	{
		SeriesID:     SeriesDFII10,
		NameZh:       "10Y TIPS 实际收益率",
		Section:      SectionOpportunityCost,
		Unit:         "percent",
		Frequency:    "daily",
		Source:       SourceFRED,
		GoldRelation: "negative",
		PlainNote:    "持有无息黄金最核心的机会成本；实际利率下行往往直接提振金价，上行则带来压制。",
		DisplayOrder: 1,
	},
	{
		SeriesID:     SeriesDFII5,
		NameZh:       "5Y TIPS 实际收益率",
		Section:      SectionOpportunityCost,
		Unit:         "percent",
		Frequency:    "daily",
		Source:       SourceFRED,
		GoldRelation: "negative",
		PlainNote:    "中期实际利率，对美联储货币政策预期更敏感。",
		DisplayOrder: 2,
	},
	{
		SeriesID:     SeriesDGS10,
		NameZh:       "10年期美债名义收益率",
		Section:      SectionOpportunityCost,
		Unit:         "percent",
		Frequency:    "daily",
		Source:       SourceFRED,
		GoldRelation: "negative",
		PlainNote:    "全球资产定价之锚；名义利率快速飙升常在短期压制黄金，回落时利好金价。",
		DisplayOrder: 3,
	},
	{
		SeriesID:     SeriesDGS2,
		NameZh:       "2年期美债名义收益率",
		Section:      SectionOpportunityCost,
		Unit:         "percent",
		Frequency:    "daily",
		Source:       SourceFRED,
		GoldRelation: "negative",
		PlainNote:    "最贴近美联储政策利率路径预期的短端利率；下行通常意味着降息预期升温。",
		DisplayOrder: 4,
	},
	{
		SeriesID:     SeriesTreasury10Y2YSpread,
		NameZh:       "美债 10Y-2Y 期限利差",
		Section:      SectionOpportunityCost,
		Unit:         "percent",
		Frequency:    "daily",
		Source:       SourceDerived,
		GoldRelation: "neutral",
		PlainNote:    "10Y 与 2Y 美债收益率之差；倒挂转正（牛陡）常见于衰退前夕与降息周期启动，黄金往往表现活跃。",
		DisplayOrder: 5,
	},
	{
		SeriesID:     SeriesT10YIE,
		NameZh:       "10年盈亏平衡通胀率",
		Section:      SectionOpportunityCost,
		Unit:         "percent",
		Frequency:    "daily",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "债市隐含的未来 10 年平均通胀预期；通胀预期抬头通常利好黄金抗通胀属性。",
		DisplayOrder: 6,
	},
	{
		SeriesID:     SeriesFEDFUNDS,
		NameZh:       "联邦基金有效利率",
		Section:      SectionOpportunityCost,
		Unit:         "percent",
		Frequency:    "monthly",
		Source:       SourceFRED,
		GoldRelation: "negative",
		PlainNote:    "美联储基准政策利率；加息尾声与降息周期通常对黄金更友好。",
		DisplayOrder: 7,
	},
	{
		SeriesID:     SeriesTLT,
		NameZh:       "20+年期美国国债 ETF（TLT）",
		Section:      SectionOpportunityCost,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "positive",
		PlainNote:    "长端美债价格代表；TLT 走强意味着长端利率下行，通常伴随黄金机会成本降低。",
		DisplayOrder: 8,
	},
	{
		SeriesID:     SeriesIEF,
		NameZh:       "7-10年期美国国债 ETF（IEF）",
		Section:      SectionOpportunityCost,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "positive",
		PlainNote:    "中长期美债价格基准，反映债市避险与利率下行节奏。",
		DisplayOrder: 9,
	},
	{
		SeriesID:     SeriesSHV,
		NameZh:       "短期美国国债 ETF（SHV）",
		Section:      SectionOpportunityCost,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "neutral",
		PlainNote:    "类现金短债资产基准，用于对照黄金的相对收益。",
		DisplayOrder: 10,
	},
	{
		SeriesID:     SeriesSPY,
		NameZh:       "标普500 ETF（SPY）",
		Section:      SectionOpportunityCost,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "neutral",
		PlainNote:    "美股核心风险资产代表，用于观察股市风险偏好与黄金的跷跷板效应。",
		DisplayOrder: 11,
	},
	{
		SeriesID:     SeriesQQQ,
		NameZh:       "纳斯达克100 ETF（QQQ）",
		Section:      SectionOpportunityCost,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "neutral",
		PlainNote:    "美股科技成长股代表，反映高久期风险资产情绪。",
		DisplayOrder: 12,
	},

	// 3. dollar_liquidity
	{
		SeriesID:     SeriesDTWEXBGS,
		NameZh:       "广义美元指数",
		Section:      SectionDollarLiquidity,
		Unit:         "index",
		Frequency:    "daily",
		Source:       SourceFRED,
		GoldRelation: "negative",
		PlainNote:    "美元兑一篮子贸易加权货币汇率；美元走弱通常直接推升以美元计价的国际金价。",
		DisplayOrder: 1,
	},
	{
		SeriesID:     SeriesDEXCHUS,
		NameZh:       "美元兑人民币汇率",
		Section:      SectionDollarLiquidity,
		Unit:         "CNY/USD",
		Frequency:    "daily",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "人民币兑美元贬值（数值上升）会在国际金价之外额外抬升国内人民币金价。",
		DisplayOrder: 2,
	},
	{
		SeriesID:     SeriesNFCI,
		NameZh:       "芝加哥联储金融条件指数",
		Section:      SectionDollarLiquidity,
		Unit:         "index",
		Frequency:    "weekly",
		Source:       SourceFRED,
		GoldRelation: "neutral",
		PlainNote:    "低于 0 代表金融环境偏宽松，高于 0 代表收紧；剧烈收紧初期黄金可能承压，随后受益于避险与宽松预期。",
		DisplayOrder: 3,
	},

	// 4. inflation_growth
	{
		SeriesID:     SeriesPCEYoY,
		NameZh:       "核心 PCE 同比",
		Section:      SectionInflationGrowth,
		Unit:         "percent",
		Frequency:    "monthly",
		Source:       SourceDerived,
		GoldRelation: "positive",
		PlainNote:    "美联储最看重的通胀指标；温和回落利于降息，而粘性偏高则强化黄金抗滞胀需求。",
		DisplayOrder: 1,
	},
	{
		SeriesID:     SeriesPCEPILFE,
		NameZh:       "核心 PCE 物价指数",
		Section:      SectionInflationGrowth,
		Unit:         "index",
		Frequency:    "monthly",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "剔除食品能源后的美国个人消费支出物价绝对指数，用于计算核心 PCE 同比。",
		DisplayOrder: 2,
	},
	{
		SeriesID:     SeriesCPIAUCSL,
		NameZh:       "美国 CPI 消费者物价指数",
		Section:      SectionInflationGrowth,
		Unit:         "index",
		Frequency:    "monthly",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "美国城市居民消费物价总水平，长期衡量法币购买力缩水速度。",
		DisplayOrder: 3,
	},
	{
		SeriesID:     SeriesIPMAN,
		NameZh:       "美国制造业工业产出指数",
		Section:      SectionInflationGrowth,
		Unit:         "index",
		Frequency:    "monthly",
		Source:       SourceFRED,
		GoldRelation: "neutral",
		PlainNote:    "实体经济景气度指标；制造业走弱往往提升避险与货币宽松预期。",
		DisplayOrder: 4,
	},
	{
		SeriesID:     SeriesUNRATE,
		NameZh:       "美国失业率",
		Section:      SectionInflationGrowth,
		Unit:         "percent",
		Frequency:    "monthly",
		Source:       SourceFRED,
		GoldRelation: "positive",
		PlainNote:    "失业率趋势性抬升通常倒逼美联储转向宽松，对黄金形成中长期利好。",
		DisplayOrder: 5,
	},

	// 5. official_market
	{
		SeriesID:     SeriesGoldUSD,
		NameZh:       "国际黄金价格（COMEX）",
		Section:      SectionOfficialMarket,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "neutral",
		PlainNote:    "美元/盎司计价的国际黄金期货主力收盘价，是全球黄金定价基准。",
		DisplayOrder: 1,
	},
	{
		SeriesID:     SeriesGoldCNY,
		NameZh:       "理论人民币金价",
		Section:      SectionOfficialMarket,
		Unit:         "CNY/g",
		Frequency:    "daily",
		Source:       SourceDerived,
		GoldRelation: "neutral",
		PlainNote:    "按国际金价与美元兑人民币汇率折算的每克理论人民币金价，用来对照国内盘面价差。",
		DisplayOrder: 2,
	},
	{
		SeriesID:     SeriesShanghaiPremium,
		NameZh:       "上海金溢价率",
		Section:      SectionOfficialMarket,
		Unit:         "percent",
		Frequency:    "daily",
		Source:       SourceDerived,
		GoldRelation: "positive",
		PlainNote:    "国内金价相对国际折算价的溢价百分比；高溢价说明国内买盘火热但也意味着买贵了，折价则性价比更高。",
		DisplayOrder: 3,
	},
	{
		SeriesID:     SeriesSilver,
		NameZh:       "国际白银价格（COMEX）",
		Section:      SectionOfficialMarket,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "positive",
		PlainNote:    "兼具贵金属与工业属性；牛市中后段白银往往弹性更大。",
		DisplayOrder: 4,
	},
	{
		SeriesID:     SeriesGoldSilverRatio,
		NameZh:       "金银比（Gold/Silver）",
		Section:      SectionOfficialMarket,
		Unit:         "ratio",
		Frequency:    "daily",
		Source:       SourceDerived,
		GoldRelation: "neutral",
		PlainNote:    "1 盎司黄金可兑换的白银盎司数；高位回落通常意味着贵金属板块情绪扩散升温。",
		DisplayOrder: 5,
	},
	{
		SeriesID:     SeriesOil,
		NameZh:       "WTI 原油价格",
		Section:      SectionOfficialMarket,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "positive",
		PlainNote:    "能源通胀与地缘风险的重要风向标，油价急涨易推升通胀预期。",
		DisplayOrder: 6,
	},
	{
		SeriesID:     SeriesGoldOilRatio,
		NameZh:       "金油比（Gold/Oil）",
		Section:      SectionOfficialMarket,
		Unit:         "ratio",
		Frequency:    "daily",
		Source:       SourceDerived,
		GoldRelation: "neutral",
		PlainNote:    "1 盎司黄金可兑换的原油桶数；极高值往往对应经济衰退担忧或避险情绪浓厚。",
		DisplayOrder: 7,
	},
	{
		SeriesID:     SeriesXAU,
		NameZh:       "费城金银矿业指数（XAU）",
		Section:      SectionOfficialMarket,
		Unit:         "index",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "positive",
		PlainNote:    "北美主流黄金白银矿企股指数，常反映权益市场对金价盈利弹性的定价。",
		DisplayOrder: 8,
	},
	{
		SeriesID:     SeriesHUI,
		NameZh:       "NYSE Arca 金矿指数（HUI）",
		Section:      SectionOfficialMarket,
		Unit:         "index",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "positive",
		PlainNote:    "未做长期套保的纯金矿股指数，对金价趋势和市场风险偏好高度敏感。",
		DisplayOrder: 9,
	},

	// 6. risk_temperature
	{
		SeriesID:     SeriesGVZCLS,
		NameZh:       "黄金隐含波动率（GVZ）",
		Section:      SectionRiskTemperature,
		Unit:         "percent",
		Frequency:    "daily",
		Source:       SourceFRED,
		GoldRelation: "neutral",
		PlainNote:    "黄金版恐慌指数；高于近 3 年 85% 分位时意味着短期剧烈波动风险加大，切忌满仓追涨杀跌。",
		DisplayOrder: 1,
	},
	{
		SeriesID:     SeriesGLD,
		NameZh:       "SPDR 黄金 ETF 持仓（吨）",
		Section:      SectionRiskTemperature,
		Unit:         "tons",
		Frequency:    "daily",
		Source:       SourceSPDR,
		GoldRelation: "positive",
		PlainNote:    "全球最大黄金 ETF 的真实实物黄金持有吨数，直接体现欧美机构资金流入流出。",
		DisplayOrder: 2,
	},
	{
		SeriesID:     SeriesGLDPrice,
		NameZh:       "SPDR 黄金 ETF 价格（GLD）",
		Section:      SectionRiskTemperature,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceYahoo,
		GoldRelation: "positive",
		PlainNote:    "GLD 场内收盘价，并在 SPDR 实物持仓源异常时作为资金动量的兜底参考。",
		DisplayOrder: 3,
	},
	{
		SeriesID:     SeriesGoldCOT,
		NameZh:       "CFTC 黄金管理基金净多头",
		Section:      SectionRiskTemperature,
		Unit:         "contracts",
		Frequency:    "weekly",
		Source:       SourceCFTC,
		GoldRelation: "positive",
		PlainNote:    "COMEX 黄金期货对冲基金净多头合约数；处于历史极高位时往往提示短期交易过于拥挤。",
		DisplayOrder: 4,
	},
	{
		SeriesID:     SeriesGoldMA,
		NameZh:       "国际金价 200 日年线",
		Section:      SectionRiskTemperature,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceDerived,
		GoldRelation: "neutral",
		PlainNote:    "国际金价 200 交易日简单移动均线（年线），衡量中长期趋势位置与安全边际。",
		DisplayOrder: 5,
	},
	{
		SeriesID:     SeriesBTCUSD,
		NameZh:       "比特币价格",
		Section:      SectionRiskTemperature,
		Unit:         "usd",
		Frequency:    "daily",
		Source:       SourceBitcoin,
		GoldRelation: "neutral",
		PlainNote:    "数字稀缺资产代表，用于对照全球流动性风险偏好与替代资产走势。",
		DisplayOrder: 6,
	},
	{
		SeriesID:     SeriesBTCMCap,
		NameZh:       "比特币总市值",
		Section:      SectionRiskTemperature,
		Unit:         "billion_usd",
		Frequency:    "daily",
		Source:       SourceBitcoin,
		GoldRelation: "neutral",
		PlainNote:    "比特币流通总市值（十亿美元），便于与黄金总市值体量进行跨资产比较。",
		DisplayOrder: 7,
	},
}

func Sections() []SectionMeta {
	out := make([]SectionMeta, len(defaultSections))
	copy(out, defaultSections)
	return out
}

func Catalog() []SeriesMeta {
	out := make([]SeriesMeta, len(defaultCatalog))
	copy(out, defaultCatalog)
	return out
}

func FindSeries(seriesID string) (SeriesMeta, bool) {
	for _, s := range defaultCatalog {
		if s.SeriesID == seriesID {
			return s, true
		}
	}
	return SeriesMeta{}, false
}

func IsValidSection(sectionID string) bool {
	for _, s := range defaultSections {
		if s.ID == sectionID {
			return true
		}
	}
	return false
}

type FREDSeriesSpec struct {
	SeriesID string
	ScaleDiv float64 // divide raw FRED value by ScaleDiv if > 0
	Decimals int     // round precision if >= 0
}

func FREDSeriesSpecs() []FREDSeriesSpec {
	return []FREDSeriesSpec{
		{SeriesID: SeriesDFII10, Decimals: 4},
		{SeriesID: SeriesDFII5, Decimals: 4},
		{SeriesID: SeriesT10YIE, Decimals: 4},
		{SeriesID: SeriesDGS10, Decimals: 4},
		{SeriesID: SeriesDGS2, Decimals: 4},
		{SeriesID: SeriesDTWEXBGS, Decimals: 4},
		{SeriesID: SeriesDEXCHUS, Decimals: 4},
		{SeriesID: SeriesNFCI, Decimals: 4},
		{SeriesID: SeriesPCEPILFE, Decimals: 4},
		{SeriesID: SeriesCPIAUCSL, Decimals: 4},
		{SeriesID: SeriesIPMAN, Decimals: 4},
		{SeriesID: SeriesUNRATE, Decimals: 4},
		{SeriesID: SeriesFYFSGDA188S, Decimals: 4},
		{SeriesID: SeriesGFDEBTN, ScaleDiv: 1e6, Decimals: 4}, // FRED returns million USD -> trillion USD
		{SeriesID: SeriesGFDEGDQ188S, Decimals: 4},
		{SeriesID: SeriesFYOINT, Decimals: 2},
		{SeriesID: SeriesFYFR, Decimals: 2},
		{SeriesID: SeriesGVZCLS, Decimals: 4},
		{SeriesID: SeriesFEDFUNDS, Decimals: 4},
		{SeriesID: SeriesWALCL, ScaleDiv: 1e3, Decimals: 4}, // FRED returns million USD -> billion USD
	}
}

type YahooSeriesSpec struct {
	SeriesID string
	Ticker   string
}

func YahooSeriesSpecs() []YahooSeriesSpec {
	return []YahooSeriesSpec{
		{SeriesID: SeriesGoldUSD, Ticker: "GC=F"},
		{SeriesID: SeriesSilver, Ticker: "SI=F"},
		{SeriesID: SeriesOil, Ticker: "CL=F"},
		{SeriesID: SeriesSPY, Ticker: "SPY"},
		{SeriesID: SeriesQQQ, Ticker: "QQQ"},
		{SeriesID: SeriesTLT, Ticker: "TLT"},
		{SeriesID: SeriesIEF, Ticker: "IEF"},
		{SeriesID: SeriesSHV, Ticker: "SHV"},
		{SeriesID: SeriesXAU, Ticker: "^XAU"},
		{SeriesID: SeriesHUI, Ticker: "^HUI"},
		{SeriesID: SeriesGLDPrice, Ticker: "GLD"},
	}
}
