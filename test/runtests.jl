using Test
using Dex
using HTTP
using JSON

function createconfig(workdir::String)
    cfg = """issuer: http://127.0.0.1:9999/dex
storage:
  type: sqlite3
  config:
    file: $workdir/conf/dex.db
web:
  http: 127.0.0.1:8080
logger:
  level: "debug"
  format: "text"
staticClients:
- id: local
  redirectURIs:
    - 'http://127.0.0.1:8888/auth/login'
  name: 'test client'
  secret: '000000000000000000000000'
oauth2:
  skipApprovalScreen: true
enablePasswordDB: true
staticPasswords:
- email: "admin@example.com"
  # bcrypt hash of the string "password"
  hash: "\$2a\$10\$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W"
  username: "admin"
  userID: "08a8684b-db88-4b73-90a9-3cd1661f5466"
"""
    cfgfile = joinpath(workdir, "test.cfg")

    open(cfgfile, "w") do f
        println(f, cfg)
    end

    cfgfile
end

function test_dex_config()
    body = ""

    @info("waiting for dex to come up")
    # try for 10 secs
    while isempty(body)
        sleep(2)
        try
            resp = HTTP.get("http://127.0.0.1:8080/dex/.well-known/openid-configuration")
            body = String(resp.body)
        catch ex
            @info("dex not ready yet...")
        end
    end

    isempty(body) && error("dex did not come up")

    spec = JSON.parse(body)
    @info("testing dex openid configuration")
    @test spec["issuer"] == "http://127.0.0.1:9999/dex"
    @test spec["userinfo_endpoint"] == "http://127.0.0.1:9999/dex/userinfo"
    @test spec["token_endpoint"] == "http://127.0.0.1:9999/dex/token"
    @test spec["jwks_uri"] == "http://127.0.0.1:9999/dex/keys"
    nothing
end

function test()
    workdir = mktempdir()

    dex = DexCtx(workdir)
    @test !isrunning(dex)

    mkpath(workdir)
    cfgfile = createconfig(workdir)
    dex = DexCtx(workdir)

    @info("setting up Dex", workdir)
    setup(dex, cfgfile)
    @test isfile(Dex.conffile(dex))

    @info("starting Dex")
    start(dex)
    sleep(2)
    @test isfile(Dex.pidfile(dex))
    @test isrunning(dex)

    test_dex_config()

    @info("restarting Dex")
    restart(dex; delay_seconds=2)
    sleep(2)
    @test isfile(Dex.pidfile(dex))
    @test isrunning(dex)

    test_dex_config()

    @info("stopping Dex")
    stop(dex)
    sleep(2)
    @test !isfile(Dex.pidfile(dex))
    @test !isrunning(dex)
    @test isfile(Dex.logfile(dex))

    @info("starting Dex (with custom logger)")
    pipe = PipeBuffer()
    start(dex; log=pipe)
    sleep(2)
    @test isfile(Dex.pidfile(dex))
    @test isrunning(dex)

    @info("checking new DexCtx")
    dex2 = DexCtx(workdir)
    @test isrunning(dex2)

    @info("stopping Dex (with custom logger)")
    stop(dex)
    sleep(2)
    @test !isfile(Dex.pidfile(dex))
    @test !isrunning(dex)
    logbytes = readavailable(pipe)
    @test !isempty(logbytes)
    @test findfirst("listening", String(logbytes)) !== nothing

    @test_throws Exception setup(dex, cfgfile)
    @test nothing === setup(dex, cfgfile; force=true)

    @info("cleaning up")
    rm(workdir; recursive=true, force=true)
    @info("done")

    nothing
end

test()
