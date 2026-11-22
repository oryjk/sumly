package com.oryjk.sumly.bootstrap

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.Surface
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.oryjk.sumly.core.network.ApiClient
import com.oryjk.sumly.design.GoldColors
import com.oryjk.sumly.design.GoldTheme
import com.oryjk.sumly.features.account.AccountViewModel
import com.oryjk.sumly.features.account.createAccountViewModel
import com.oryjk.sumly.features.chanlun.ChanlunScreen
import com.oryjk.sumly.features.holdings.HoldingsViewModel
import com.oryjk.sumly.features.macro.BackendMacroService
import com.oryjk.sumly.features.macro.MacroViewModel
import com.oryjk.sumly.features.market.BackendGoldMarketService
import com.oryjk.sumly.features.market.MarketBasis
import com.oryjk.sumly.features.market.MarketViewModel
import com.oryjk.sumly.features.widget.GoldQuoteWidget
import com.oryjk.sumly.ui.navigation.SumlyWorkspace
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )

        val context = applicationContext
        val api = ApiClient()
        val workspaces = HoldingsWorkspaces(context, api)
        val marketSettings = context.getSharedPreferences("sumly_market", MODE_PRIVATE)
        val provider = ViewModelProvider(this, viewModelFactory {
            initializer {
                val storedBasis = marketSettings.getString("basis", null)
                MarketViewModel(
                    BackendGoldMarketService(api, File(context.cacheDir, "sumly-market-history")),
                    initialBasis = MarketBasis.entries.firstOrNull { it.name == storedBasis } ?: MarketBasis.Domestic,
                    onBasisSelected = { basis ->
                        marketSettings.edit().putString("basis", basis.name).apply()
                        GoldQuoteWidget.requestRefresh(context)
                    },
                )
            }
            initializer { createAccountViewModel(api, context, onAccountDeleted = workspaces::erase) }
            initializer { MacroViewModel(BackendMacroService(api)) }
        })

        val market = provider[MarketViewModel::class.java]
        val holdings = ViewModelProvider(this, viewModelFactory {
            initializer { HoldingsViewModel(workspaces.guestStore, historicalPrice = market::historicalPurchasePrice) }
        })[HoldingsViewModel::class.java]
        val account = provider[AccountViewModel::class.java]
        val macro = provider[MacroViewModel::class.java]

        setContent {
            GoldTheme {
                Surface(color = GoldColors.Background, contentColor = GoldColors.Text) {
                    SumlyWorkspace(
                        market = market,
                        guestHoldings = holdings,
                        account = account,
                        macro = macro,
                        guestStore = workspaces.guestStore,
                        openAccount = { workspaces.open(account.session, it) },
                    ) { onClose, onSignIn ->
                        ChanlunScreen(account, api, onClose = onClose, onSignIn = onSignIn)
                    }
                }
            }
        }
    }
}
