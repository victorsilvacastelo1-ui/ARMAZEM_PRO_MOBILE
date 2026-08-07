package com.br.armazempro.app

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import com.br.armazempro.app.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private var fileChooserCallback: ValueCallback<Array<Uri>>? = null

    private val fileChooserLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        fileChooserCallback?.onReceiveValue(
            WebChromeClient.FileChooserParams.parseResult(result.resultCode, result.data)
        )
        fileChooserCallback = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(binding.webView, true)

        binding.webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_DEFAULT
            mediaPlaybackRequiresUserGesture = false
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            loadWithOverviewMode = true
            useWideViewPort = true
            textZoom = 100
            userAgentString = "$userAgentString ArmazemProAndroid/3.0"
        }

        binding.webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                return if (isAllowed(uri)) false else {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    true
                }
            }

            override fun onPageFinished(view: WebView, url: String) {
                binding.swipeRefresh.isRefreshing = false
                binding.progressBar.isVisible = false
                binding.webView.isVisible = true
                binding.offlineView.isVisible = false
                binding.syncStatus.text = getString(R.string.sincronizado)
                injectMobileCss(view)
            }
        }

        binding.webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                binding.progressBar.progress = newProgress
                binding.progressBar.isVisible = newProgress in 1..99
            }

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                fileChooserCallback?.onReceiveValue(null)
                fileChooserCallback = filePathCallback
                return try {
                    fileChooserLauncher.launch(fileChooserParams?.createIntent())
                    true
                } catch (_: ActivityNotFoundException) {
                    fileChooserCallback = null
                    false
                }
            }
        }

        binding.swipeRefresh.setOnRefreshListener { reload() }
        binding.refreshButton.setOnClickListener { reload() }
        binding.retryButton.setOnClickListener { loadSystem() }
        binding.backButton.setOnClickListener { goBack() }

        binding.bottomNavigation.setOnItemSelectedListener { item ->
            when (item.itemId) {
                R.id.nav_dashboard -> openSection(listOf("Dashboard", "Início", "Inicio"))
                R.id.nav_produtos -> openSection(listOf("Produtos", "Produto"))
                R.id.nav_entradas -> openSection(listOf("Entrada", "Entradas"))
                R.id.nav_saidas -> openSection(listOf("Saída", "Saidas", "Saídas", "Saida"))
                R.id.nav_mais -> openMoreMenu()
            }
            true
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (binding.webView.canGoBack()) binding.webView.goBack()
                else AlertDialog.Builder(this@MainActivity)
                    .setTitle(R.string.sair_app)
                    .setMessage(R.string.deseja_sair)
                    .setNegativeButton(R.string.cancelar, null)
                    .setPositiveButton(R.string.sair) { _, _ -> finish() }
                    .show()
            }
        })

        loadSystem()
    }

    private fun loadSystem() {
        if (!hasInternet()) return showOffline()
        binding.syncStatus.text = getString(R.string.carregando)
        binding.offlineView.isVisible = false
        binding.webView.isVisible = true
        binding.webView.loadUrl(BuildConfig.APP_URL)
    }

    private fun reload() {
        if (!hasInternet()) {
            binding.swipeRefresh.isRefreshing = false
            showOffline()
        } else {
            binding.syncStatus.text = getString(R.string.carregando)
            binding.webView.reload()
        }
    }

    private fun goBack() {
        if (binding.webView.canGoBack()) binding.webView.goBack()
        else binding.webView.loadUrl(BuildConfig.APP_URL)
    }

    private fun openSection(labels: List<String>) {
        if (!hasInternet()) return showOffline()
        val jsLabels = labels.joinToString(",") { "'${it.replace("'", "\\'")}'" }
        val js = """
            (function(){
              const wanted = [$jsLabels].map(x=>x.toLowerCase());
              const els = [...document.querySelectorAll('a,button,[role=button],nav *,.sidebar *,.menu *')];
              const hit = els.find(el => {
                const t=(el.innerText||el.textContent||'').trim().toLowerCase();
                return wanted.some(w => t===w || t.startsWith(w+' '));
              });
              if(hit){ hit.click(); return 'clicked'; }
              return 'not-found';
            })();
        """.trimIndent()
        binding.webView.evaluateJavascript(js) { result ->
            if (result.contains("not-found")) {
                binding.webView.loadUrl(BuildConfig.APP_URL)
            }
        }
    }

    private fun openMoreMenu() {
        val options = arrayOf("Inventário", "Kits", "Armazéns", "Devolução", "Equipe", "Sistema completo")
        AlertDialog.Builder(this)
            .setTitle("Mais funções")
            .setItems(options) { _, which ->
                when (which) {
                    0 -> openSection(listOf("Inventário", "Inventario"))
                    1 -> openSection(listOf("Kits", "Kit"))
                    2 -> openSection(listOf("Armazéns", "Armazens", "Armazém"))
                    3 -> openSection(listOf("Devolução", "Devolucao"))
                    4 -> openSection(listOf("Equipe", "Membros"))
                    else -> binding.webView.loadUrl(BuildConfig.APP_URL)
                }
            }.show()
    }

    private fun injectMobileCss(webView: WebView) {
        val js = """
            (function(){
              let m=document.querySelector('meta[name=viewport]');
              if(!m){m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}
              m.content='width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover';
              if(document.getElementById('ap-mobile-3')) return;
              const s=document.createElement('style'); s.id='ap-mobile-3';
              s.textContent=`
                html,body{max-width:100vw!important;overflow-x:hidden!important;-webkit-text-size-adjust:100%!important}
                input,select,textarea,button{font-size:16px!important;min-height:42px}
                img,svg,canvas{max-width:100%!important;height:auto}
                table{display:block!important;width:100%!important;overflow-x:auto!important;-webkit-overflow-scrolling:touch}
                [role=dialog],.modal,.modal-content{max-width:calc(100vw - 20px)!important;margin-left:auto!important;margin-right:auto!important}
                @media(max-width:760px){
                  .container,.content,.main,.page,.dashboard,main{max-width:100%!important;min-width:0!important;padding-left:10px!important;padding-right:10px!important}
                  .row,.cards,.grid{flex-wrap:wrap!important;grid-template-columns:1fr!important}
                  form{max-width:100%!important}
                  input,select,textarea{max-width:100%!important;width:100%!important;box-sizing:border-box!important}
                }
              `;
              document.head.appendChild(s);
            })();
        """.trimIndent()
        webView.evaluateJavascript(js, null)
    }

    private fun showOffline() {
        binding.webView.isVisible = false
        binding.offlineView.isVisible = true
        binding.syncStatus.text = getString(R.string.offline)
    }

    private fun hasInternet(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun isAllowed(uri: Uri): Boolean {
        val host = uri.host?.lowercase().orEmpty()
        return host == "armazempro.com.br" || host.endsWith(".armazempro.com.br") ||
            host.endsWith(".supabase.co") || host.endsWith(".mercadopago.com.br") ||
            host == "api.mercadopago.com"
    }
}
