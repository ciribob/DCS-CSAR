local csarSlotBlock = {} -- DONT REMOVE!!!
--[[

   CSAR Slot Blocking - V1.9.1
   
   Put this file in C:/Users/<YOUR USERNAME>/DCS/Scripts for 1.5 or C:/Users/<YOUR USERNAME>/DCS.openalpha/Scripts for 2.0
   
   This script will use flags to disable and enable slots when a pilot is shot down and ejects.

   The flags will NOT interfere with mission flags

 ]]

csarSlotBlock.showEnabledMessage = true -- if set to true, the player will be told that the slot is enabled when switching to it
csarSlotBlock.version = "1.9.1"

-- Logic for determining if player is allowed in a slot
function csarSlotBlock.shouldAllowSlot(_playerID, _slotID) -- _slotID == Unit ID unless its multi aircraft in which case slotID is unitId_seatID

if csarSlotBlock.csarSlotBlockEnabled() then

    local _unitId = csarSlotBlock.getUnitId(_slotID);

    local _mode = csarSlotBlock.csarMode()

    if _mode == 1  then
        -- disable aircraft for ALL pilots

        local _flag = csarSlotBlock.getFlagValue("CSAR_AIRCRAFT".._unitId)

        if _flag == 100 then
            return false
        end

        return true


    elseif _mode == 2 then
        -- disable aircraft for a certain player

        local _playerName = net.get_player_info(_playerID, 'name')

        if _playerName == nil then
            return true
        end

        local _flag = csarSlotBlock.getFlagValue("CSAR_AIRCRAFT".._playerName:gsub('%W','').."_".._unitId)

        if _flag == 100 then
            return false
        end

        return true

    elseif _mode == 3 then
        -- global lives limit

        local _playerName = net.get_player_info(_playerID, 'name')

        if _playerName == nil then
            return true
        end

        local _flag = csarSlotBlock.getFlagValue("CSAR_PILOT".._playerName:gsub('%W',''))

        if _flag == 1 then
            return false
        else
            return true
        end

    end
end
    return true

end

function csarSlotBlock.getFlagValue(_flag)

    local _status,_error  = net.dostring_in('server', " return trigger.misc.getUserFlag(\"".._flag.."\"); ")

    if not _status and _error then
        net.log("error getting flag: ".._error)
        return 0
    else
        --  net.log("flag value ".._unitId.." value: ".._status)

        --disabled
        return tonumber(_status)
    end
end

-- _slotID == Unit ID unless its multi aircraft in which case slotID is unitId_seatID
function csarSlotBlock.getUnitId(_slotID)
    local _unitId = tostring(_slotID)
    if string.find(tostring(_unitId),"_",1,true) then
        --extract substring
        _unitId = string.sub(_unitId,1,string.find(_unitId,"_",1,true))
        net.log("Unit ID Substr ".._unitId)
    end

    return tonumber(_unitId)
end



--DOC
-- onGameEvent(eventName,arg1,arg2,arg3,arg4)
--"friendly_fire", playerID, weaponName, victimPlayerID
--"mission_end", winner, msg
--"kill", killerPlayerID, killerUnitType, killerSide, victimPlayerID, victimUnitType, victimSide, weaponName
--"self_kill", playerID
--"change_slot", playerID, slotID, prevSide
--"connect", id, name
--"disconnect", ID_, name, playerSide
--"crash", playerID, unit_missionID
--"eject", playerID, unit_missionID
--"takeoff", playerID, unit_missionID, airdromeName
--"landing", playerID, unit_missionID, airdromeName
--"pilot_death", playerID, unit_missionID
--
csarSlotBlock.onGameEvent = function(eventName,playerID,arg2,arg3,arg4) -- This stops the user flying again after crashing or other events

    if  DCS.isServer() and DCS.isMultiplayer() then
        if DCS.getModelTime() > 1 then  -- must check this to prevent a possible CTD by using a_do_script before the game is ready to use a_do_script. -- Source GRIMES :)

            if eventName == "self_kill"
                    or eventName == "crash"
                    or eventName == "eject"
                    or eventName ==  "pilot_death" then

                -- is player in a slot and valid?
                local _playerDetails = net.get_player_info(playerID)

                if _playerDetails ~=nil and _playerDetails.side ~= 0 and _playerDetails.slot ~= "" and _playerDetails.slot ~= nil then

                    local _allow = csarSlotBlock.shouldAllowSlot(playerID, _playerDetails.slot)

                    if not _allow then
                        csarSlotBlock.rejectPlayer(playerID)
                    end

                end
            end
        end
    end
end

csarSlotBlock.onPlayerTryChangeSlot = function(playerID, side, slotID)

    if  DCS.isServer() and DCS.isMultiplayer() then
        if  (side ~=0 and  slotID ~='' and slotID ~= nil)  then

            local _allow = csarSlotBlock.shouldAllowSlot(playerID,slotID)

            if not _allow then
                csarSlotBlock.rejectPlayer(playerID)

                return false
            else

                local _playerName = net.get_player_info(playerID, 'name')

                if _playerName ~= nil and csarSlotBlock.showEnabledMessage and
                        csarSlotBlock.csarSlotBlockEnabled() and csarSlotBlock.csarMode() > 0 then
                    --Disable chat message to user
                    local _chatMessage = string.format("*** %s - Aircraft Enabled! If you will need to be rescued by CSAR. Make sure you eject and Protect the Helis! ***",_playerName)
                    net.send_chat_to(_chatMessage, playerID)
                end

            end

            net.log("CSAR - allowing -  playerid: "..playerID.." side:"..side.." slot: "..slotID)

        end
    end

    return true

end

csarSlotBlock.csarSlotBlockEnabled = function()

    local _res = csarSlotBlock.getFlagValue("CSAR_SLOTBLOCK")

    return _res == 100

end


csarSlotBlock.csarMode = function()

    local _mode = csarSlotBlock.getFlagValue("CSAR_MODE")

    return _mode

end

csarSlotBlock.rejectPlayer = function(playerID)
    net.log("Reject Slot - force spectators - "..playerID)

    -- put to spectators
    net.force_player_slot(playerID, 0, '')

    local _playerName = net.get_player_info(playerID, 'name')

    if _playerName ~= nil then
        --Disable chat message to user
        local _chatMessage = string.format("*** Sorry %s - Slot DISABLED, Pilot has been shot down and needs to be rescued by CSAR ***",_playerName)
        net.send_chat_to(_chatMessage, playerID)
    end
end

csarSlotBlock.trimStr = function(_str)

    return  string.format( "%s", _str:match( "^%s*(.-)%s*$" ) )
end

DCS.setUserCallbacks(csarSlotBlock)

net.log("Loaded - CSAR SLOT BLOCK k v"..csarSlotBlock.version.. " by Ciribob")