module Dex

include("../deps/deps.jl")

export DexCtx
export setup, start, stop, restart, isrunning

const webtemplates = abspath(joinpath(dirname(@__FILE__), "../deps/usr/lib/webtemplates.tar.gz"))

function __init__()
    check_deps()
    if !isfile(webtemplates)
        error("$(webtemplates) does not exist, Please re-run Pkg.build(\"Dex\"), and restart Julia.")
    end
end

mutable struct DexCtx
    workdir::String
    proc::Union{Base.Process,Nothing}
    pid::Union{Int,Nothing}

    function DexCtx(workdir)
        ctx = new(workdir, nothing, nothing)
        pfile = pidfile(ctx)
        if isfile(pfile)
            ctx.pid = parse(Int, read(pidfile(ctx), String))
            isrunning(ctx)
        end
        ctx
    end
end

webdir(ctx::DexCtx) = joinpath(ctx.workdir, "web")
confdir(ctx::DexCtx) = joinpath(ctx.workdir, "conf")
conffile(ctx::DexCtx) = joinpath(confdir(ctx), "dexconfig.yaml")
logsdir(ctx::DexCtx) = joinpath(ctx.workdir, "logs")
pidfile(ctx::DexCtx) = joinpath(logsdir(ctx), "dex.pid")
logfile(ctx::DexCtx) = joinpath(logsdir(ctx), "dex.log")

function setup(ctx::DexCtx, configfile::String, templates::Union{String,Nothing}=nothing; force::Bool=false, reset_templates::Bool=(templates !== nothing))
    existing_setup = isdir(confdir(ctx)) && isdir(webdir(ctx)) && isdir(logsdir(ctx))

    existing_setup && !force && error("setup already exists, specify force=true to overwrite")

    # make the workdir
    for path in (webdir(ctx), confdir(ctx), logsdir(ctx))
        isdir(path) || mkpath(path)
    end

    # place configuration file
    (force || !isfile(conffile(ctx))) && cp(configfile, conffile(ctx); force=true)

    if reset_templates || !existing_setup
        # extract bundled templates
        run(`tar -xzf $webtemplates -C $(webdir(ctx))`)

        # copy over user provided templates
        (templates !== nothing) && run(`cp -R -f $(joinpath(templates, ".")) $(webdir(ctx))`)
    end
    nothing
end

function start(ctx::DexCtx; log=logfile(ctx), append::Bool=isa(log,AbstractString))
    config = conffile(ctx)
    command = Cmd(`$dex serve $config`; detach=true, dir=ctx.workdir)
    redirected_command = pipeline(command, stdout=log, stderr=log, append=append)
    ctx.proc = run(redirected_command; wait=false)
    ctx.pid = getpid(ctx.proc)
    open(joinpath(logsdir(ctx), "dex.pid"), "a") do file
        println(file, ctx.pid)
    end
    nothing
end

isrunning(ctx::DexCtx) = (ctx.pid !== nothing) ? isrunning(ctx, ctx.pid) : false
function isrunning(ctx::DexCtx, pid::Int)
    cmdlinefile = "/proc/$pid/cmdline"
    if isfile(cmdlinefile)
        cmdline = read(cmdlinefile, String)
        if occursin(dex, cmdline) && occursin(confdir(ctx), cmdline)
            # process still running
            return true
        end
    end

    ctx.pid = nothing
    ctx.proc = nothing
    rm(pidfile(ctx); force=true)
    false
end

function stop(ctx::DexCtx)
    if isrunning(ctx)
        if ctx.proc !== nothing
            kill(ctx.proc)
        else
            run(Cmd(`/usr/bin/pkill -P $(ctx.pid)`; ignorestatus=true))
            run(`/bin/kill $(ctx.pid)`)
        end
        ctx.pid = nothing
        ctx.proc = nothing
        rm(pidfile(ctx); force=true)
    end
    nothing
end

function restart(ctx::DexCtx; delay_seconds::Int=0)
    stop(ctx)
    (delay_seconds > 0) && sleep(delay_seconds)
    start(ctx)
end

end
