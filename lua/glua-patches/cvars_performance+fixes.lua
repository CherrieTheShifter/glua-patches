---@diagnostic disable: undefined-global

-- ConVar performance module
--
-- Forces a small set of client performance convars, keeping a one-time backup of
-- whatever the user had before so it can be put back.
--
-- Realm: CLIENT.

if CLIENT then

    local dir_path = "glua_patches"
    local file_path = "glua_patches/cvars.json"

    -- Applied whenever the module is enabled.
    local base_list = {
        [ "studio_queue_mode" ] = "1",
        [ "r_fastzreject" ] = "1"
    }

    -- Part of GMod's multicore set ( gmod_mcore_test / mat_queue_mode / cl_threaded_bone_setup ).
    -- Source default is 0, and there is a long history of players being unable to launch the
    -- game after enabling it, so this group is opt-in and off by default.
    -- Recovery if it ever happens: add +cl_threaded_bone_setup 0 to the launch options.
    local multicore_list = {
        [ "cl_threaded_bone_setup" ] = "1"
    }

    -- Deliberately not included:
    --   r_queued_ropes  - Source already defaults this to 1, so forcing it does nothing.
    --   r_sse2          - removed from the game in the September 2026 update.
    --   snd_* / dsp_*   - the September 2026 update blocks the saved ones from Lua.

    local cv_enable = CreateClientConVar( "glua_patches_cvars_optimization", "1", true, false, "Force a set of client performance convars. Set to 0 to restore your original values.", 0, 1 )
    local cv_multicore = CreateClientConVar( "glua_patches_cvars_multicore", "0", true, false, "Also force the multicore convars. Off by default, these have a history of launch crashes.", 0, 1 )

    -- Returns the ConVar only if it exists and we are actually allowed to change it.
    -- The September 2026 update marked more convars as cheats, so this check matters.
    local function GetWritable( name )
        local cvar = GetConVar( name )
        if cvar == nil then return nil end
        if cvar:IsFlagSet( FCVAR_CHEAT ) then return nil end
        return cvar
    end

    local function Each( list, fn )
        for name, value in pairs( list ) do
            fn( name, value )
        end
    end

    local function ReadBackup()
        if not file.Exists( file_path, "DATA" ) then return {} end

        local raw = file.Read( file_path, "DATA" )
        if raw == nil then return {} end

        return util.JSONToTable( raw ) or {}
    end

    local function WriteBackup( saved )
        if not file.IsDir( dir_path, "DATA" ) then
            file.CreateDir( dir_path )
        end

        file.Write( file_path, util.TableToJSON( saved, true ) )
    end

    -- Only ever records a convar the FIRST time we touch it. Without this guard a second
    -- run would back up the values we already forced, destroying the user's originals.
    local function BackupGroup( list )
        local saved = ReadBackup()
        local changed = false

        Each( list, function( name )
            if saved[ name ] ~= nil then return end

            local cvar = GetWritable( name )
            if cvar == nil then return end

            saved[ name ] = cvar:GetString()
            changed = true
        end )

        if changed then
            WriteBackup( saved )
        end
    end

    local function ApplyGroup( list )
        Each( list, function( name, value )
            if GetWritable( name ) == nil then return end
            RunConsoleCommand( name, value )
        end )
    end

    -- Puts a group back and drops it from the backup, so it is re-recorded fresh next time.
    local function RestoreGroup( list )
        local saved = ReadBackup()
        local changed = false

        Each( list, function( name )
            local value = saved[ name ]
            if value == nil then return end

            if GetWritable( name ) ~= nil then
                RunConsoleCommand( name, value )
            end

            saved[ name ] = nil
            changed = true
        end )

        if not changed then return end

        if next( saved ) == nil then
            file.Delete( file_path )
        else
            WriteBackup( saved )
        end
    end

    local function Refresh()
        if cv_enable:GetBool() then
            BackupGroup( base_list )
            ApplyGroup( base_list )

            if cv_multicore:GetBool() then
                BackupGroup( multicore_list )
                ApplyGroup( multicore_list )
            else
                RestoreGroup( multicore_list )
            end
        else
            RestoreGroup( base_list )
            RestoreGroup( multicore_list )
        end
    end

    -- Initialize is early. Give the console a tick to be ready before issuing commands.
    hook.Add( "Initialize", "glua.Patches - ConVar performance", function()
        timer.Simple( 0, Refresh )
    end )

    cvars.AddChangeCallback( "glua_patches_cvars_optimization", function()
        Refresh()
    end, "glua.Patches - ConVar performance" )

    cvars.AddChangeCallback( "glua_patches_cvars_multicore", function()
        Refresh()
    end, "glua.Patches - ConVar performance" )

    -- Manual escape hatch, in case something goes wrong and you want everything back now.
    concommand.Add( "glua_patches_cvars_restore", function()
        RestoreGroup( base_list )
        RestoreGroup( multicore_list )
        RunConsoleCommand( "glua_patches_cvars_optimization", "0" )
        MsgN( "[glua-patches] Restored your original convar values." )
    end, nil, "Restore the convar values this module changed." )

end
