# configs/services.ps1
# 服務定義表 — 生產(prod) / 測試(test) 環境分離。
#
# Schema 對齊 gs-gh-summary repo_paths panel：
#   Repo / SubPath / HostIP / Port → 對應 owner/name / path / host_ip / server_port
#
# 此檔純資料，無邏輯。由下列腳本載入：
#   scripts/start-env.ps1   啟動服務
#   scripts/stop-env.ps1    停止服務
#   scripts/status-env.ps1  查看狀態
#
# Port 規則：Prod = 原始預設 port；Test = Prod + 100（部分 + 100 有衝突則另行標注）
# HostIP 規則：Prod = LAN IP（可跨機器連線）；Test = 127.0.0.1（僅本機）

$GS_SERVICES = [ordered]@{

    # ──────────────────────────────────────────────────────
    # gs-trading-portal
    # Port via: python server.py --port P --bind B
    # ──────────────────────────────────────────────────────
    "gs-trading-portal" = @{
        Repo        = "gsinvest017-ai/gs-trading-portal"
        SubPath     = "gs-trading-portal"
        Description = "交易入口 Genesis gold UI"
        Prod        = @{
            Port    = 8123
            HostIP  = "192.168.0.249"
            Cmd     = @("python", "server.py", "--port", "8123", "--bind", "0.0.0.0")
            EnvVars = @{}
        }
        Test        = @{
            Port    = 8223
            HostIP  = "127.0.0.1"
            Cmd     = @("python", "server.py", "--port", "8223", "--bind", "127.0.0.1")
            EnvVars = @{}
        }
    }

    # ──────────────────────────────────────────────────────
    # gs-gh-summary
    # Port via: python server.py --port P --host H
    # ──────────────────────────────────────────────────────
    "gs-gh-summary" = @{
        Repo        = "gsinvest017-ai/gs-gh-summary"
        SubPath     = "gs-gh-summary"
        Description = "GitHub 活動摘要看板"
        Prod        = @{
            Port    = 8790
            HostIP  = "192.168.0.249"
            Cmd     = @("python", "server.py", "--port", "8790", "--host", "192.168.0.249")
            EnvVars = @{}
        }
        Test        = @{
            Port    = 8890
            HostIP  = "127.0.0.1"
            Cmd     = @("python", "server.py", "--port", "8890", "--host", "127.0.0.1")
            EnvVars = @{}
        }
    }

    # ──────────────────────────────────────────────────────
    # tw-news-board
    # Port via: $env:TWBOARD_PORT / $env:TWBOARD_HOST
    # ──────────────────────────────────────────────────────
    "tw-news-board" = @{
        Repo        = "gsinvest017-ai/tw-news-board"
        SubPath     = "tw-news-board"
        Description = "台股期貨消息面看板"
        Prod        = @{
            Port    = 8787
            HostIP  = "192.168.0.249"
            Cmd     = @("python", "serve.py")
            EnvVars = @{ TWBOARD_PORT = "8787"; TWBOARD_HOST = "192.168.0.249" }
        }
        Test        = @{
            Port    = 8887
            HostIP  = "127.0.0.1"
            Cmd     = @("python", "serve.py")
            EnvVars = @{ TWBOARD_PORT = "8887"; TWBOARD_HOST = "127.0.0.1" }
        }
    }

    # ──────────────────────────────────────────────────────
    # tw-sentiment-radar
    # Port via: $env:TWRADAR_PORT / $env:TWRADAR_HOST
    # 依賴 tw-news-board（用 TWBOARD_PORT/HOST 指向同環境的 board）
    # ──────────────────────────────────────────────────────
    "tw-sentiment-radar" = @{
        Repo        = "gsinvest017-ai/tw-sentiment-radar"
        SubPath     = "tw-sentiment-radar"
        Description = "台股情緒雷達（需搭配 tw-news-board）"
        Prod        = @{
            Port    = 8788
            HostIP  = "192.168.0.249"
            Cmd     = @("python", "serve.py")
            EnvVars = @{
                TWRADAR_PORT  = "8788"
                TWRADAR_HOST  = "192.168.0.249"
                TWBOARD_PORT  = "8787"
                TWBOARD_HOST  = "192.168.0.249"
            }
        }
        Test        = @{
            Port    = 8888
            HostIP  = "127.0.0.1"
            Cmd     = @("python", "serve.py")
            EnvVars = @{
                TWRADAR_PORT  = "8888"
                TWRADAR_HOST  = "127.0.0.1"
                TWBOARD_PORT  = "8887"
                TWBOARD_HOST  = "127.0.0.1"
            }
        }
    }

    # ──────────────────────────────────────────────────────
    # gs-risk-manager
    # Port via: python -m dashboard --port P
    # venv at gs-risk-manager/.venv（run.ps1 自動建立）
    # ──────────────────────────────────────────────────────
    "gs-risk-manager" = @{
        Repo        = "gsinvest017-ai/gs-risk-manager"
        SubPath     = "gs-risk-manager"
        Description = "風險管理 dashboard"
        Prod        = @{
            Port    = 5066
            HostIP  = "192.168.0.249"
            Cmd     = @(".venv\Scripts\python.exe", "-m", "dashboard", "--port", "5066")
            EnvVars = @{}
        }
        Test        = @{
            Port    = 5166
            HostIP  = "127.0.0.1"
            Cmd     = @(".venv\Scripts\python.exe", "-m", "dashboard", "--port", "5166")
            EnvVars = @{}
        }
    }

    # ──────────────────────────────────────────────────────
    # autogo
    # Port via: uvicorn --host H --port P
    # venv at autogo/.venv
    # ──────────────────────────────────────────────────────
    "autogo" = @{
        Repo        = "gsinvest017-ai/autogo"
        SubPath     = "autogo"
        Description = "Windows 桌面螢幕 agent dashboard"
        Prod        = @{
            Port    = 8765
            HostIP  = "192.168.0.249"
            Cmd     = @(".venv\Scripts\python.exe", "-m", "uvicorn", "web.app:app",
                        "--host", "192.168.0.249", "--port", "8765")
            EnvVars = @{}
        }
        Test        = @{
            Port    = 8865
            HostIP  = "127.0.0.1"
            Cmd     = @(".venv\Scripts\python.exe", "-m", "uvicorn", "web.app:app",
                        "--host", "127.0.0.1", "--port", "8865")
            EnvVars = @{}
        }
    }

    # ──────────────────────────────────────────────────────
    # gs-scraper  ⚠️  Test 環境暫不支援
    # ui/search/app.py L262: port = 5050（hardcoded，無 env override）
    # 不動 codebase 的前提下無法在不同 port 啟動第二個實例。
    # ──────────────────────────────────────────────────────
    "gs-scraper" = @{
        Repo        = "gsinvest017-ai/gs-scraper"
        SubPath     = "gs-scraper"
        Description = "QUANTDATA 搜尋 UI"
        Note        = "Test=null: ui/search/app.py L262 hardcodes port 5050, no env override."
        Prod        = @{
            Port    = 5050
            HostIP  = "0.0.0.0"
            Cmd     = @(".venv\Scripts\python.exe", "-m", "ui.search.app")
            EnvVars = @{}
        }
        Test        = $null
    }

    # ──────────────────────────────────────────────────────
    # trading-SySTEM  （多服務）
    # Prod: run.ps1 一鍵起 KGI(5100) + sim(5101) + Streamlit(8501)
    # Test: 僅起 Streamlit UI 於不同 port；KGI/sim backend 沿用 prod（純資料源可共用）
    # ──────────────────────────────────────────────────────
    "trading-SySTEM" = @{
        Repo        = "gsinvest017-ai/trading-SySTEM"
        SubPath     = "trading-SySTEM"
        Description = "實盤交易系統（KGI + Sinopac sim + Streamlit UI）"
        Note        = "Test: 只啟動 Streamlit UI(8601)；KGI(5100)/sim(5101) backend 沿用 prod，不重複啟動。"
        Prod        = @{
            Port    = 8501
            HostIP  = "192.168.0.249"
            # run.ps1 一鍵啟動所有子服務
            Cmd     = @("pwsh", "-File", "run.ps1")
            EnvVars = @{ TRADING_ENV = "prod" }
        }
        Test        = @{
            Port    = 8601
            HostIP  = "127.0.0.1"
            # 只啟動 Streamlit；KGI/sim 已在 prod 跑，不重複起
            Cmd     = @("venv\Scripts\python.exe", "-m", "streamlit", "run", "app.py",
                        "--server.port", "8601", "--server.address", "127.0.0.1")
            EnvVars = @{ TRADING_ENV = "test"; KGI_PORT = "5100"; SIM_PORT = "5101" }
        }
    }
}
