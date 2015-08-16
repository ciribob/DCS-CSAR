-- CSAR Script for DCS Ciribob  2015
-- Version 1.2 - 16/8/2015

csar = {}

-- SETTINGS FOR MISSION DESIGNER vvvvvvvvvvvvvvvvvv
csar.csarUnits = { "MEDEVAC #1", "MEDEVAC #2", "MEDEVAC #3", "MEDEVAC #4", "MEDEVAC #5", "MEDEVAC RED #1" } -- List of all the MEDEVAC _UNIT NAMES_ (the line where it says "Pilot" in the ME)!

csar.bluemash = { "BlueMASH #1", "BlueMASH #2" } -- The unit that serves as MASH for the blue side
csar.redmash = { "RedMASH #1", "RedMASH #2" } -- The unit that serves as MASH for the red side

csar.disableAircraft = true -- DISABLE player aircraft until the pilot is rescued?

csar.disableAircraftTimeout = true -- Allow aircraft to be used after 20 minutes if the pilot isnt rescued
csar.disableTimeoutTime = 20 -- Time in minutes for TIMEOUT

csar.enableForAI = false -- set to false to disable AI units from being rescued.

csar.bluesmokecolor = 4 -- Color of smokemarker for blue side, 0 is green, 1 is red, 2 is white, 3 is orange and 4 is blue
csar.redsmokecolor = 1 -- Color of smokemarker for red side, 0 is green, 1 is red, 2 is white, 3 is orange and 4 is blue

csar.requestdelay = 2 -- Time in seconds before the survivors will request Medevac

csar.coordtype = 3 -- Use Lat/Long DDM (0), Lat/Long DMS (1), MGRS (2), Bullseye imperial (3) or Bullseye metric (4) for coordinates.
csar.coordaccuracy = 1 -- Precision of the reported coordinates, see MIST-docs at http://wiki.hoggit.us/view/GetMGRSString
-- only applies to _non_ bullseye coords

csar.immortalcrew = true -- Set to true to make wounded crew immortal
csar.invisiblecrew = true -- Set to true to make wounded crew insvisible

csar.messageTime = 30 -- Time to show the intial wounded message for in seconds

-- If you set it less than 25 the troops might not move close enough
csar.loadDistance = 50 -- configure distance for troops to get in helicopter in meters.

csar.radioSound = "beacon.ogg" -- the name of the sound file to use for the Pilot radio beacons. If this isnt added to the mission BEACONS WONT WORK!

-- SETTINGS FOR MISSION DESIGNER ^^^^^^^^^^^^^^^^^^^*

-- Sanity checks of mission designer
assert(mist ~= nil, "\n\n** HEY MISSION-DESIGNER! **\n\nMiST has not been loaded!\n\nMake sure MiST 3.7 or higher is running\n*before* running this script!\n")

csar.addedTo = {}

csar.downedPilotCounterRed = 0
csar.downedPilotCounterBlue = 0

csar.woundedGroups = {} -- contains the new group of units
csar.inTransitGroups = {} -- contain a table for each SAR with all units he has with the
-- original name of the killed group

csar.radioBeacons = {}

csar.smokeMarkers = {} -- tracks smoke markers for groups
csar.heliVisibleMessage = {} -- tracks if the first message has been sent of the heli being visible

csar.heliCloseMessage = {} -- tracks heli close message  ie heli < 500m distance

csar.radioBeacons = {} -- all current beacons

csar.max_units = 5 --number of pilots that can be carried

csar.currentlyDisabled = {} --stored disabled aircraft

csar.hoverStatus = {} -- tracks status of a helis hover above a downed pilot

function csar.tableLength(T)

    if T == nil then
        return 0
    end


    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

function csar.pilotsOnboard(_heliName)
    local count = 0
    if csar.inTransitGroups[_heliName] then
        for _, _group in pairs(csar.inTransitGroups[_heliName]) do
            count = count + 1
        end
    end
    return count
end

-- Handles all world events
csar.eventHandler = {}
function csar.eventHandler:onEvent(_event)
    local status, err = pcall(function(_event)

        if _event == nil or _event.initiator == nil then
            return false

        elseif _event.id == 15 then

            -- if its a sar heli, re-add check status script
            for _, _heliName in pairs(csar.csarUnits) do

                if _heliName == _event.initiator:getName() then
                    -- add back the status script
                    for _woundedName, _groupInfo in pairs(csar.woundedGroups) do

                        if _groupInfo.side == _event.initiator:getCoalition() then

                            --env.info(string.format("Schedule Respawn %s %s",_heliName,_woundedName))
                            -- queue up script
                            -- Schedule timer to check when to pop smoke
                            timer.scheduleFunction(csar.checkWoundedGroupStatus, { _heliName, _woundedName }, timer.getTime() + 5)
                        end
                    end
                end
            end

            return true
        elseif (_event.id == 9) then
            -- Pilot dead
            trigger.action.outTextForCoalition(_event.initiator:getCoalition(), "MAYDAY MAYDAY! " .. _event.initiator:getTypeName() .. " shot down. No Chute!", 10)

            --remove status messages for each Heli?

            return

        elseif world.event.S_EVENT_EJECTION == _event.id then

            env.info("Event unit - Pilot Ejected")

            local _unit = _event.initiator

            if csar.enableForAI == false and _unit:getPlayerName() == nil then

                return
            end

            local _spawnedGroup = csar.spawnGroup(_unit)
            csar.addSpecialParametersToGroup(_spawnedGroup)

            trigger.action.outTextForCoalition(_unit:getCoalition(), "MAYDAY MAYDAY! " .. _unit:getTypeName() .. " shot down. Chute Spotted!", 10)

            local _freq = csar.generateADFFrequency()

            csar.addBeaconToGroup(_spawnedGroup:getName(),_freq)

            -- Generate DESCRIPTION text
            local _text = " "
            if _unit:getPlayerName() ~= nil then
                _text =  "Pilot ".._unit:getPlayerName().." of ".._unit:getName().." - ".._unit:getTypeName()
            else
                _text = "AI Pilot of ".._unit:getName().." - ".._unit:getTypeName()
            end

            --mark plane as broken and unflyable
            if _unit:getPlayerName() ~= nil and csar.disableAircraft == true then
                csar.currentlyDisabled[_unit:getName()] = {timeout =  csar.disableTimeoutTime*60 + timer.getTime(),desc=_text}
                timer.scheduleFunction(csar.checkDisabledAircraftStatus, _unit:getName(), timer.getTime() + 1)
            end

            --store the old group under the new group name
            csar.woundedGroups[_spawnedGroup:getName()] = { originalGroup = _unit:getGroup():getName(), side = _spawnedGroup:getCoalition(), originalUnit = _unit:getName(), frequency= _freq, desc = _text }

            csar.initSARForPilot(_spawnedGroup,_freq)

            --dont add until we're done processing...
            --table.insert(medevac.deadUnits, _event.initiator)
        end
    end, _event)
    if (not status) then
        env.error(string.format("Error while handling event %s", err), csar.displayerrordialog)
    end
end

function csar.checkDisabledAircraftStatus(_name)

    local _details = csar.currentlyDisabled[_name]

    if  _details ~= nil then

        if csar.disableAircraftTimeout and timer.getTime() > _details.timeout then

            --remove from disabled
            csar.currentlyDisabled[_name] = nil

            return
        end
        local _unit = Unit.getByName(_name)

        if  _unit ~=  nil then

            --display message,
            csar.displayMessageToSAR(_unit, _details.desc .. " needs to be rescued before this aircraft can be flown again!", 10)
            --destroy in 20 seconds
            timer.scheduleFunction(csar.destroyUnit, _name, timer.getTime() + 20)

            --queue up in 25 seconds

            timer.scheduleFunction(csar.checkDisabledAircraftStatus, _name, timer.getTime() + 25)
            return
        end
    else
        return -- stop checking
    end

    timer.scheduleFunction(csar.checkDisabledAircraftStatus, _name, timer.getTime() + 1)

end

function csar.destroyUnit(_unitName)
    local _unit = Unit.getByName(_unitName)

    if _unit ~= nil then
        _unit:destroy()
    end
end

csar.addBeaconToGroup = function(_woundedGroupName, _freq)

    local _group = Group.getByName(_woundedGroupName)

    if _group == nil then

        --return frequency to pool of available
        for _i, _current in ipairs(csar.usedVHFFrequencies) do
            if _current == _freq then
                table.insert(ctld.freeVHFFrequencies, _freq)
                table.remove(ctld.usedVHFFrequencies, _i)
            end
        end

        return
    end

    --        local _coordinatesText =  string.format("%s at %s - %.2f KHz ADF ", _woundedGroupName, csar.getPositionOfWounded(_group), _freq/1000)
    --
    --        local _setFrequency = {
    --            ["enabled"] = true,
    --            ["auto"] = false,
    --            ["id"] = "WrappedAction",
    --            ["number"] = 1, -- first task
    --            ["params"] = {
    --                ["action"] = {
    --                    ["id"] = "SetFrequency",
    --                    ["params"] = {
    --                        ["modulation"] = 0, -- 0 is AM 1 is FM --if FM you cant read the message... might be the only fix to stop FC3 aircraft hearing it... :(
    --                        ["frequency"] =_freq,
    --                    },
    --                },
    --            },
    --        }
    --
    --        local _setupDetails = {
    --            ["enabled"] = true,
    --            ["auto"] = false,
    --            ["id"] = "WrappedAction",
    --            ["number"] = 2, -- second task
    --            ["params"] = {
    --                ["action"] = {
    --                    ["id"] = "TransmitMessage",
    --                    ["params"] = {
    --                        ["loop"] = true, --false works too
    --                        ["subtitle"] = _coordinatesText, --_text
    --                        ["duration"] =  60, -- reset every 60 seconds --used to have timer.getTime() +60
    --                        ["file"] = csar.radioSound,
    --                    },
    --                },
    --            }
    --        }
    --
    --        local _groupController = _group:getController()
    --
    --        --reset!
    --        _groupController:resetTask()
    --
    --       _groupController:setTask(_setFrequency)
    --       _groupController:setTask(_setupDetails)
    --
    --        --Make the unit NOT engage
    --       _groupController:setOption(AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)

    trigger.action.radioTransmission(csar.radioSound, _group:getUnit(1):getPoint(), 0, false, _freq, 1000)

    timer.scheduleFunction(csar.refreshRadioBeacon, { _woundedGroupName, _freq }, timer.getTime() + 30)
end

csar.refreshRadioBeacon = function(_args)

    csar.addBeaconToGroup(_args[1],_args[2])
end

csar.addSpecialParametersToGroup = function(_spawnedGroup)

    -- Immortal code for alexej21
    local _setImmortal = {
        id = 'SetImmortal',
        params = {
            value = true
        }
    }
    -- invisible to AI, Shagrat
    local _setInvisible = {
        id = 'SetInvisible',
        params = {
            value = true
        }
    }

    local _controller = _spawnedGroup:getController()

    if (csar.immortalcrew) then
        Controller.setCommand(_controller, _setImmortal)
    end

    if (csar.invisiblecrew) then
        Controller.setCommand(_controller, _setInvisible)
    end
end

function csar.spawnGroup(_deadUnit)

    local _id = mist.getNextGroupId()

    local  _groupName = "Downed Pilot #" .. _id

    local _side = _deadUnit:getCoalition()

    local _pos = _deadUnit:getPoint()

    local _group = {
        ["visible"] = false,
        ["groupId"] =_id,
        ["hidden"] = false,
        ["units"] = {},
        ["name"] = _groupName,
        ["task"] = {},
    }

    if _side == 2 then
        _group.units[1] = csar.createUnit(_pos.x + 50, _pos.z + 50, 120, "Soldier M4")
    else
        _group.units[1] = csar.createUnit(_pos.x + 50, _pos.z + 50, 120, "Infantry AK")
    end

    _group.category = Group.Category.GROUND;
    _group.country = _deadUnit:getCountry();

    local _spawnedGroup = Group.getByName(mist.dynAdd(_group).name)

    return _spawnedGroup
end


function csar.createUnit(_x, _y, _heading, _type)

    local _id = mist.getNextUnitId();

    local _name = string.format("Wounded Pilot #%s", _id)

    local _newUnit = {
        ["y"] = _y,
        ["type"] = _type,
        ["name"] = _name,
        ["unitId"] = _id,
        ["heading"] = _heading,
        ["playerCanDrive"] = false,
        ["skill"] = "Excellent",
        ["x"] = _x,
    }

    return _newUnit
end

function csar.initSARForPilot(_downedGroup,_freq)

    local _leader = _downedGroup:getUnit(1)

    local _coordinatesText = csar.getPositionOfWounded(_downedGroup)

    local
    _text = string.format("%s requests SAR at %s, beacon at %.2f KHz",
        _leader:getName(), _coordinatesText, _freq/1000)

    local _randPercent = math.random(1, 100)

    -- Loop through all the medevac units
    for x, _heliName in pairs(csar.csarUnits) do
        local _status, _err = pcall(function(_args)
            local _unitName = _args[1]
            local _woundedSide = _args[2]
            local _medevacText = _args[3]
            local _leaderPos = _args[4]
            local _groupName = _args[5]
            local _group = _args[6]

            local _heli = csar.getSARHeli(_unitName)

            -- queue up for all SAR, alive or dead, we dont know the side if they're dead or not spawned so check
            --coalition in scheduled smoke

            if _heli ~= nil then

                -- Check coalition side
                if (_woundedSide == _heli:getCoalition()) then
                    -- Display a delayed message
                    timer.scheduleFunction(csar.delayedHelpMessage, { _unitName, _medevacText, _groupName }, timer.getTime() + csar.requestdelay)

                    -- Schedule timer to check when to pop smoke
                    timer.scheduleFunction(csar.checkWoundedGroupStatus, { _unitName, _groupName }, timer.getTime() + 1)
                end
            else
                --env.warning(string.format("Medevac unit %s not active", _heliName), false)

                -- Schedule timer for Dead unit so when the unit respawns he can still pickup units
                --timer.scheduleFunction(medevac.checkStatus, {_unitName,_groupName}, timer.getTime() + 5)
            end
        end, { _heliName, _leader:getCoalition(), _text, _leader:getPoint(), _downedGroup:getName(), _downedGroup })

        if (not _status) then
            env.warning(string.format("Error while checking with medevac-units %s", _err))
        end
    end
end

function csar.checkWoundedGroupStatus(_argument)

    local _status, _err = pcall(function(_args)
        local _heliName = _args[1]
        local _woundedGroupName = _args[2]

        local _woundedGroup = csar.getWoundedGroup(_woundedGroupName)
        local _heliUnit = csar.getSARHeli(_heliName)

        -- if wounded group is not here then message alread been sent to SARs
        -- stop processing any further
        if csar.woundedGroups[_woundedGroupName] == nil then
            return
        end

        if _heliUnit == nil then
            -- stop wounded moving, head back to smoke as target heli is DEAD

            -- in transit cleanup
            --  csar.inTransitGroups[_heliName] = nil
            return
        end

        -- double check that this function hasnt been queued for the wrong side

        if csar.woundedGroups[_woundedGroupName].side ~= _heliUnit:getCoalition() then
            return --wrong side!
        end

        if csar.checkGroupNotKIA(_woundedGroup, _woundedGroupName, _heliUnit, _heliName) then

            local _woundedLeader = _woundedGroup[1]
            local _lookupKeyHeli = _heliUnit:getID() .. "_" .. _woundedLeader:getID() --lookup key for message state tracking

            local _distance = csar.getDistance(_heliUnit:getPoint(), _woundedLeader:getPoint())

            if _distance < 3000 then

                if csar.checkCloseWoundedGroup(_distance, _heliUnit, _heliName, _woundedGroup, _woundedGroupName) == true then
                    -- we're close, reschedule
                    timer.scheduleFunction(csar.checkWoundedGroupStatus, _args, timer.getTime() + 1)
                end

            else
                csar.heliVisibleMessage[_lookupKeyHeli] = nil

                --reschedule as units arent dead yet , schedule for a bit slower though as we're far away
                timer.scheduleFunction(csar.checkWoundedGroupStatus, _args, timer.getTime() + 5)
            end
        end
    end, _argument)

    if not _status then

        env.error(string.format("error checkWoundedGroupStatus %s", _err))
    end
end

function csar.popSmokeForGroup(_woundedGroupName, _woundedLeader)
    -- have we popped smoke already in the last 5 mins
    local _lastSmoke = csar.smokeMarkers[_woundedGroupName]
    if _lastSmoke == nil or timer.getTime() > _lastSmoke then

        local _smokecolor
        if (_woundedLeader:getCoalition() == 2) then
            _smokecolor = csar.bluesmokecolor
        else
            _smokecolor = csar.redsmokecolor
        end
        trigger.action.smoke(_woundedLeader:getPoint(), _smokecolor)

        csar.smokeMarkers[_woundedGroupName] = timer.getTime() + 300 -- next smoke time
    end
end

function csar.pickupUnit(_heliUnit,_pilotName,_woundedGroup,_woundedGroupName)

    local _woundedLeader = _woundedGroup[1]

    -- GET IN!
    local _heliName = _heliUnit:getName()
    local _groups = csar.inTransitGroups[_heliName]
    local _unitsInHelicopter = csar.pilotsOnboard(_heliName)

    -- init table if there is none for this helicopter
    if not _groups then
        csar.inTransitGroups[_heliName] = {}
        _groups = csar.inTransitGroups[_heliName]
    end

    -- if the heli can't pick them up, show a message and return
    if _unitsInHelicopter + 1 > csar.max_units then
        csar.displayMessageToSAR(_heliUnit, string.format("%s, %s. We're already crammed with %d guys! Sorry!",
            _pilotName, _heliName, _unitsInHelicopter, _unitsInHelicopter), 10)
        return true
    end

    csar.inTransitGroups[_heliName][_woundedGroupName] =
    {
        originalGroup = csar.woundedGroups[_woundedGroupName].originalGroup,
        originalUnit = csar.woundedGroups[_woundedGroupName].originalUnit,
        woundedGroup = _woundedGroupName,
        side = _heliUnit:getCoalition(),
        desc = csar.woundedGroups[_woundedGroupName].desc
    }

    Group.destroy(_woundedLeader:getGroup())

    csar.displayMessageToSAR(_heliUnit, string.format("%s: %s I'm in! Get to the MASH ASAP! ", _heliName, _pilotName), 10)

    timer.scheduleFunction(csar.scheduledSARFlight,
        {
            heliName = _heliUnit:getName(),
            groupName = _woundedGroupName
        },
        timer.getTime() + 1)

    return true
end


-- Helicopter is within 3km
function csar.checkCloseWoundedGroup(_distance, _heliUnit, _heliName, _woundedGroup, _woundedGroupName)

    local _woundedLeader = _woundedGroup[1]
    local _lookupKeyHeli = _heliUnit:getID() .. "_" .. _woundedLeader:getID() --lookup key for message state tracking

    local _pilotName = csar.woundedGroups[_woundedGroupName].desc

    local _woundedCount = 1

    local _reset = true

    csar.popSmokeForGroup(_woundedGroupName, _woundedLeader)

    if csar.heliVisibleMessage[_lookupKeyHeli] == nil then

        csar.displayMessageToSAR(_heliUnit, string.format("%s: %s. I hear you! Damn that thing is loud! Land or hover by the smoke.", _heliName,_pilotName), 30)

        --mark as shown for THIS heli and THIS group
        csar.heliVisibleMessage[_lookupKeyHeli] = true
    end

    if (_distance < 500) then

        if csar.heliCloseMessage[_lookupKeyHeli] == nil then

            csar.displayMessageToSAR(_heliUnit, string.format("%s: %s. You're close now! Land or hover at the smoke.", _heliName, _pilotName), 10)

            --mark as shown for THIS heli and THIS group
            csar.heliCloseMessage[_lookupKeyHeli] = true
        end

        -- have we landed close enough?
        if csar.inAir(_heliUnit) == false then

            -- if you land on them, doesnt matter if they were heading to someone else as you're closer, you win! :)
            if (_distance < csar.loadDistance) then

                return csar.pickupUnit(_heliUnit,_pilotName,_woundedGroup,_woundedGroupName)
            end

        else

            local _unitsInHelicopter = csar.pilotsOnboard(_heliName)

            if  csar.inAir(_heliUnit) and _unitsInHelicopter + 1 <= csar.max_units then

                if _distance < 8.0  then

                    --check height!
                    local _height = _heliUnit:getPoint().y - _woundedLeader:getPoint().y

                    if _height  <= 20.0 then

                        local _time = csar.hoverStatus[_lookupKeyHeli]

                        if _time == nil then
                            csar.hoverStatus[_lookupKeyHeli] = 10
                            _time = 10
                        else
                            _time = csar.hoverStatus[_lookupKeyHeli] - 1
                            csar.hoverStatus[_lookupKeyHeli] = _time
                        end

                        if _time > 0 then
                            csar.displayMessageToSAR(_heliUnit, "Hovering above " .. _pilotName .. ". \n\nHold hover for " .. _time .. " seconds to winch them up. \n\nIf the countdown stops you're too far away!", 10)
                        else
                            csar.hoverStatus[_lookupKeyHeli] = nil
                            return csar.pickupUnit(_heliUnit,_pilotName,_woundedGroup,_woundedGroupName)
                        end
                        _reset = false
                    else
                        csar.displayMessageToSAR(_heliUnit, "Too high to winch " .. _pilotName .. " \nReduce height and hover for 10 seconds!", 5)
                    end
                end
            end
        end
    end

    if _reset then
        csar.hoverStatus[_lookupKeyHeli] = nil
    end

    return true
end



function csar.checkGroupNotKIA(_woundedGroup, _woundedGroupName, _heliUnit, _heliName)

    -- check if unit has died or been picked up
    if #_woundedGroup == 0 and _heliUnit ~= nil then

        local inTransit = false

        for _currentHeli, _groups in pairs(csar.inTransitGroups) do

            if _groups[_woundedGroupName] then
                local _group = _groups[_woundedGroupName]
                if _group.side == _heliUnit:getCoalition() then
                    inTransit = true

                    csar.displayToAllSAR(string.format("%s has been picked up by %s", _woundedGroupName, _currentHeli), _heliUnit:getCoalition(), _heliName)

                    break
                end
            end
        end


        --display to all sar
        if inTransit == false then
            --DEAD

            csar.displayToAllSAR(string.format("%s is KIA ", _woundedGroupName), _heliUnit:getCoalition(), _heliName)
        end

        --     medevac.displayMessageToSAR(_heliUnit, string.format("%s: %s is dead", _heliName,_woundedGroupName ),10)

        --stops the message being displayed again
        csar.woundedGroups[_woundedGroupName] = nil

        return false
    end

    --continue
    return true
end


function csar.scheduledSARFlight(_args)

    local _status, _err = pcall(function(_args)

        local _heliUnit = csar.getSARHeli(_args.heliName)
        local _woundedGroupName = _args.groupName

        if (_heliUnit == nil) then

            -- Put intransit pilots back
            --TODO possibly respawn the guys
            local _rescuedGroups = csar.inTransitGroups[_args.heliName]

            if _rescuedGroups ~= nil then

                -- enable pilots again
                for _, _rescueGroup in pairs(_rescuedGroups) do
                    csar.currentlyDisabled[_rescueGroup.originalUnit] = nil
                end

            end

            csar.inTransitGroups[_args.heliName] = nil

            return
        end

        if csar.inTransitGroups[_heliUnit:getName()] == nil or csar.inTransitGroups[_heliUnit:getName()][_woundedGroupName] == nil then
            -- Groups already rescued
            return
        end


        local _dist = csar.getClosetMASH(_heliUnit)

        if _dist == -1 then

            -- Mash Dead
            csar.inTransitGroups[_heliUnit:getName()][_woundedGroupName] = nil

            csar.displayMessageToSAR(_heliUnit, string.format("%s: NO MASH! The pilot died of despair!", _heliUnit:getName()), 10)

            return
        end

        if _dist < 200 and _heliUnit:inAir() == false then

            local _rescuedGroups = csar.inTransitGroups[_heliUnit:getName()]

            csar.inTransitGroups[_heliUnit:getName()] = nil

            local _txt = string.format("%s: The pilots have been taken to the\nmedical clinic. Good job!", _heliUnit:getName())

            -- enable pilots again
            for _, _rescueGroup in pairs(_rescuedGroups) do
                csar.currentlyDisabled[_rescueGroup.originalUnit] = nil
            end

            csar.displayMessageToSAR(_heliUnit, _txt, 10)

            return
        end

        -- end
        --queue up
        timer.scheduleFunction(csar.scheduledSARFlight,
            {
                heliName = _heliUnit:getName(),
                groupName = _woundedGroupName
            },
            timer.getTime() + 1)
    end, _args)
    if (not _status) then
        env.error(string.format("Error in scheduledSARFlight\n\n%s", _err))
    end
end


function csar.getSARHeli(_unitName)

    local _heli = Unit.getByName(_unitName)

    if _heli ~= nil and _heli:isActive() and _heli:getLife() > 0 then

        return _heli
    end

    return nil
end


-- Displays a request for medivac
function csar.delayedHelpMessage(_args)
    local status, err = pcall(function(_args)
        local _heliName = _args[1]
        local _text = _args[2]
        local _injuredGroupName = _args[3]

        local _heli = csar.getSARHeli(_heliName)

        if _heli ~= nil and #csar.getWoundedGroup(_injuredGroupName) > 0 then
            csar.displayMessageToSAR(_heli, _text, csar.messageTime)

            trigger.action.outSoundForGroup(_heli:getGroup():getID(), "CSAR.ogg")

        else
            env.info("No Active Heli or Group DEAD")
        end
    end, _args)

    if (not status) then
        env.error(string.format("Error in delayedHelpMessage "))
    end

    return nil
end


function csar.displayMessageToSAR(_unit, _text, _time)

    trigger.action.outTextForGroup(_unit:getGroup():getID(), _text, _time)
end

function csar.getWoundedGroup(_groupName)
    local _status, _result = pcall(function(_groupName)

        local _woundedGroup = {}
        local _units = Group.getByName(_groupName):getUnits()

        for _, _unit in pairs(_units) do

            if _unit ~= nil and _unit:isActive() and _unit:getLife() > 0 then
                table.insert(_woundedGroup, _unit)
            end
        end

        return _woundedGroup
    end, _groupName)

    if (_status) then
        return _result
    else
        --env.warning(string.format("getWoundedGroup failed! Returning 0.%s",_result), false)
        return {} --return empty table
    end
end


function csar.convertGroupToTable(_group)

    local _unitTable = {}

    for _, _unit in pairs(_group:getUnits()) do

        if _unit ~= nil and _unit:getLife() > 0 then
            table.insert(_unitTable, _unit:getName())
        end
    end

    return _unitTable
end

function csar.getPositionOfWounded(_woundedGroup)

    local _woundedTable = csar.convertGroupToTable(_woundedGroup)

    local _coordinatesText = ""
    if csar.coordtype == 0 then -- Lat/Long DMTM
    _coordinatesText = string.format("%s", mist.getLLString({ units = _woundedTable, acc = csar.coordaccuracy, DMS = 0 }))

    elseif csar.coordtype == 1 then -- Lat/Long DMS
    _coordinatesText = string.format("%s", mist.getLLString({ units = _woundedTable, acc = csar.coordaccuracy, DMS = 1 }))

    elseif csar.coordtype == 2 then -- MGRS
    _coordinatesText = string.format("%s", mist.getMGRSString({ units = _woundedTable, acc = csar.coordaccuracy }))

    elseif csar.coordtype == 3 then -- Bullseye Imperial
    _coordinatesText = string.format("bullseye %s", mist.getBRString({ units = _woundedTable, ref = coalition.getMainRefPoint(_woundedGroup:getCoalition()), alt = 0 }))

    else -- Bullseye Metric --(medevac.coordtype == 4)
    _coordinatesText = string.format("bullseye %s", mist.getBRString({ units = _woundedTable, ref = coalition.getMainRefPoint(_woundedGroup:getCoalition()), alt = 0, metric = 1 }))
    end

    return _coordinatesText
end

-- Displays all active MEDEVACS/SAR
function csar.displayActiveSAR(_unitName)
    local _msg = "Active MEDEVAC/SAR:"

    local _heli = csar.getSARHeli(_unitName)

    if _heli == nil then
        return
    end

    local _heliSide = _heli:getCoalition()

    for _groupName, _value in pairs(csar.woundedGroups) do

        local _woundedGroup = csar.getWoundedGroup(_groupName)

        if #_woundedGroup > 0 and (_woundedGroup[1]:getCoalition() == _heliSide) then

            local _coordinatesText = csar.getPositionOfWounded(_woundedGroup[1]:getGroup())

            local _distance = csar.getDistance(_heli:getPoint(), _woundedGroup[1]:getPoint())

            _msg = string.format("%s\n%s at %s - %.2f KHz ADF - %.3fKM ", _msg, _value.desc, _coordinatesText, _value.frequency/1000,_distance/1000.0)
        end
    end

    csar.displayMessageToSAR(_heli, _msg, 20)
end


function csar.getClosetDownedPilot(_heli)

    local _side = _heli:getCoalition()

    local _closetGroup = nil
    local _shortestDistance = -1
    local _distance = 0
    local _closetGroupInfo = nil

    for _woundedName, _groupInfo in pairs(csar.woundedGroups) do

            local _tempWounded = csar.getWoundedGroup(_woundedName)

            env.info(_woundedName)

            -- check group exists and not moving to someone else
            if #_tempWounded > 0 and (_tempWounded[1]:getCoalition() == _side) then

                _distance = csar.getDistance(_heli:getPoint(), _tempWounded[1]:getPoint())

                env.info(_woundedName.." ".._distance)
                if _distance ~= nil and (_shortestDistance == -1 or _distance < _shortestDistance) then


                    _shortestDistance = _distance
                    _closetGroup = _tempWounded[1]
                    _closetGroupInfo = _groupInfo

                    env.info(_woundedName.." ".._shortestDistance)
                end
            end
    end

    return {pilot=_closetGroup,distance=_shortestDistance,groupInfo=_closetGroupInfo}
end

function csar.signalFlare(_unitName)

    local _heli = csar.getSARHeli(_unitName)

    if _heli == nil then
        return
    end

   local _closet =  csar.getClosetDownedPilot(_heli)

    if _closet ~= nil then
        env.info("GOT CLOSEST")

        env.info(_closet.distance)
    end


    if _closet ~= nil and _closet.pilot ~= nil and _closet.distance < 1000.0 then

        local _clockDir = csar.getClockDirection(_heli,_closet.pilot)

        local _msg = string.format("%s - %.2f KHz ADF - %.3fM - Popping Signal Flare at your %s ",  _closet.groupInfo.desc,  _closet.groupInfo.frequency/1000,_closet.distance,_clockDir)
        csar.displayMessageToSAR(_heli, _msg, 20)

        trigger.action.signalFlare(_closet.pilot:getPoint(),1, 0 )
    else
        csar.displayMessageToSAR(_heli, "No Pilots within 1KM", 20)
    end

end

function csar.displayToAllSAR(_message, _side, _ignore)

    for _, _unitName in pairs(csar.csarUnits) do

        local _unit = csar.getSARHeli(_unitName)

        if _unit ~= nil and _unit:getCoalition() == _side then

            if _ignore == nil or _ignore ~= _unitName then
                csar.displayMessageToSAR(_unit, _message, 10)
            end
        else
            -- env.info(string.format("unit nil %s",_unitName))
        end
    end
end

function csar.getClosetMASH(_heli)

    local _mashes = csar.bluemash

    if (_heli:getCoalition() == 1) then
        _mashes = csar.redmash
    end

    local _shortestDistance = -1
    local _distance = 0

    for _, _mashName in pairs(_mashes) do

        local _mashUnit = Unit.getByName(_mashName)

        if _mashUnit ~= nil and _mashUnit:isActive() and _mashUnit:getLife() > 0 then

            _distance = csar.getDistance(_heli:getPoint(), _mashUnit:getPoint())

            if _distance ~= nil and (_shortestDistance == -1 or _distance < _shortestDistance) then

                _shortestDistance = _distance
            end
        end
    end

    if _shortestDistance ~= -1 then
        return _shortestDistance
    else
        return -1
    end
end

function csar.checkOnboard(_unitName)
    local _unit = csar.getSARHeli(_unitName)

    if _unit == nil then
        return
    end

    --list onboard pilots

    local _inTransit =  csar.inTransitGroups[_unitName]

    if _inTransit == nil or  csar.tableLength(_inTransit) == 0 then
        csar.displayMessageToSAR(_unit, "No Rescued Pilots onboard", 30)
    else

        local _text = "Onboard: "

        for _,_onboard  in pairs(csar.inTransitGroups[_unitName]) do
            _text = _text .."\n".._onboard.desc
        end

        csar.displayMessageToSAR(_unit,_text , 30)
    end
end


-- Adds menuitem to all medevac units that are active
function csar.addMedevacMenuItem()
    -- Loop through all Medevac units

    timer.scheduleFunction(csar.addMedevacMenuItem, nil, timer.getTime() + 5)

    for _, _unitName in pairs(csar.csarUnits) do

        local _unit = csar.getSARHeli(_unitName)

        if _unit ~= nil then

            local _groupId = _unit:getGroup():getID()

            if csar.addedTo[tostring(_groupId)] == nil then

                csar.addedTo[tostring(_groupId)] = true

                local _rootPath = missionCommands.addSubMenuForGroup(_groupId, "CSAR")

                missionCommands.addCommandForGroup(_groupId, "List Active CSAR", _rootPath,  csar.displayActiveSAR,
                    _unitName)

                missionCommands.addCommandForGroup(_groupId, "Check Onboard", _rootPath, csar.checkOnboard,_unitName)

                missionCommands.addCommandForGroup(_groupId, "Request Signal Flare", _rootPath, csar.signalFlare,_unitName)
            end
        else
            -- env.info(string.format("unit nil %s",_unitName))
        end
    end

    return
end

--get distance in meters assuming a Flat world
function csar.getDistance(_point1, _point2)

    local xUnit = _point1.x
    local yUnit = _point1.z
    local xZone = _point2.x
    local yZone = _point2.z

    local xDiff = xUnit - xZone
    local yDiff = yUnit - yZone

    return math.sqrt(xDiff * xDiff + yDiff * yDiff)
end

-- 200 - 400 in 10KHz
-- 400 - 850 in 10 KHz
-- 850 - 1250 in 50 KHz
function csar.generateVHFrequencies()

    --ignore list
    --list of all frequencies in KHZ that could conflict with
    -- 191 - 1290 KHz, beacon range
    local _skipFrequencies = {
        745, --Astrahan
        381,
        384,
        300.50,
        312.5,
        1175,
        342,
        735,
        300.50,
        353.00,
        440,
        795,
        525,
        520,
        690,
        625,
        291.5,
        300.50,
        435,
        309.50,
        920,
        1065,
        274,
        312.50,
        580,
        602,
        297.50,
        750,
        485,
        950,
        214,
        1025, 730, 995, 455, 307, 670, 329, 395, 770,
        380, 705, 300.5, 507, 740, 1030, 515,
        330, 309.5,
        348, 462, 905, 352, 1210, 942, 435,
        324,
        320, 420, 311, 389, 396, 862, 680, 297.5,
        920, 662,
        866, 907, 309.5, 822, 515, 470, 342, 1182, 309.5, 720, 528,
        337, 312.5, 830, 740, 309.5, 641, 312, 722, 682, 1050,
        1116, 935, 1000, 430, 577
    }

    csar.freeVHFFrequencies = {}
    csar.usedVHFFrequencies = {}

    local _start = 200000

    -- first range
    while _start < 400000 do

        -- skip existing NDB frequencies
        local _found = false
        for _, value in pairs(_skipFrequencies) do
            if value * 1000 == _start then
                _found = true
                break
            end
        end


        if _found == false then
            table.insert(csar.freeVHFFrequencies, _start)
        end

        _start = _start + 10000
    end

    _start = 400000
    -- second range
    while _start < 850000 do

        -- skip existing NDB frequencies
        local _found = false
        for _, value in pairs(_skipFrequencies) do
            if value * 1000 == _start then
                _found = true
                break
            end
        end

        if _found == false then
            table.insert(csar.freeVHFFrequencies, _start)
        end

        _start = _start + 10000
    end

    _start = 850000
    -- third range
    while _start <= 1250000 do

        -- skip existing NDB frequencies
        local _found = false
        for _, value in pairs(_skipFrequencies) do
            if value * 1000 == _start then
                _found = true
                break
            end
        end

        if _found == false then
            table.insert(csar.freeVHFFrequencies, _start)
        end

        _start = _start + 50000
    end
end

function csar.generateADFFrequency()

    if #csar.freeVHFFrequencies <= 3 then
        csar.freeVHFFrequencies = csar.usedVHFFrequencies
        csar.usedVHFFrequencies = {}
    end

    local _vhf = table.remove(csar.freeVHFFrequencies, math.random(#csar.freeVHFFrequencies))

    return _vhf
    --- return {uhf=_uhf,vhf=_vhf}
end

function csar.inAir(_heli)

    if _heli:inAir() == false then
        return false
    end

    -- less than 5 cm/s a second so landed
    -- BUT AI can hold a perfect hover so ignore AI
    if mist.vec.mag(_heli:getVelocity()) < 0.05 and _heli:getPlayerName() ~= nil then
        return false
    end
    return true
end

function csar.getClockDirection(_heli, _crate)

    -- Source: Helicopter Script - Thanks!

    local _position = _crate:getPosition().p -- get position of crate
    local _playerPosition = _heli:getPosition().p -- get position of helicopter
    local _relativePosition = mist.vec.sub(_position, _playerPosition)

    local _playerHeading = mist.getHeading(_heli) -- the rest of the code determines the 'o'clock' bearing of the missile relative to the helicopter

    local _headingVector = { x = math.cos(_playerHeading), y = 0, z = math.sin(_playerHeading) }

    local _headingVectorPerpendicular = { x = math.cos(_playerHeading + math.pi / 2), y = 0, z = math.sin(_playerHeading + math.pi / 2) }

    local _forwardDistance = mist.vec.dp(_relativePosition, _headingVector)

    local _rightDistance = mist.vec.dp(_relativePosition, _headingVectorPerpendicular)

    local _angle = math.atan2(_rightDistance, _forwardDistance) * 180 / math.pi

    if _angle < 0 then
        _angle = 360 + _angle
    end
    _angle = math.floor(_angle * 12 / 360 + 0.5)
    if _angle == 0 then
        _angle = 12
    end

    return _angle
end

csar.generateVHFrequencies()

-- Schedule timer to add radio item
timer.scheduleFunction(csar.addMedevacMenuItem, nil, timer.getTime() + 5)

world.addEventHandler(csar.eventHandler)

env.info("Medevac event handler added")
