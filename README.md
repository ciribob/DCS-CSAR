# DCS-CSAR

Simplified MEDEVAC script specifically for pilot rescue simulating Combat Search and Rescue (CSAR)

By default, any crashed plane with an ejected pilot will be disabled until the pilot is rescued and dropped back safely to a friendly MASH, Airfield or FARP

## Setup in Mission Editor

### Script Setup
**This script requires MIST version 4.0.57 or above: https://github.com/mrSkortch/MissionScriptingTools**

First make sure MIST is loaded, either as an Initialization Script  for the mission or the first DO SCRIPT with a "TIME MORE" of 1. "TIME MORE" means run the actions after X seconds into the mission.

Load the CSAR script a few seconds after MIST using a second trigger with a "TIME MORE" and a DO SCRIPT of CSAR.lua.

You will also need to load in the **beacon.ogg** sound file for Radio beacon homing. This can be done by adding a Sound To Country action. Pick an unused country, like Australia, so no one actually hears the audio when joining at the start of the mission. If you don't add the Audio file, radio beacons will not work and you will be unable to use ADF to find a downed pilot. Make sure not to rename the file as well.

### Script Configuration
The script has lots of configuration options that can be used to further customise the behaviour. Make sure after making any changes to save your file and re-add to the mission.

````lua

csar.enableAllslots = true  -- Doesn't require to set the Unit name check Aircraft Type and Limit below
csar.useprefix    = false  -- Use the Prefixed defined below, Requires Unit have the Prefix defined below
-- Prefix settting
csar.csarPrefix = { "helicargo", "MEDEVAC"}

-- All slot / Limit settings
csar.aircraftType = {} -- Type and limit
csar.aircraftType["SA342Mistral"] = 2
csar.aircraftType["SA342Minigun"] = 2
csar.aircraftType["SA342L"] = 2
csar.aircraftType["SA342M"] = 2
csar.aircraftType["UH-1H"] = 8
csar.aircraftType["Mi-8MT"] = 16



csar.csarMode = 0

    --      0 - No Limit - NO Aircraft disabling
    --      1 - Disable Aircraft when its down - Timeout to reenable aircraft
    --      2 - Disable Aircraft for Pilot when he's shot down -- timeout to reenable pilot for aircraft
    --      3 - Pilot Life Limit - No Aircraft Disabling -- timeout to reset lives?

csar.maxLives = 8 -- Maximum pilot lives

csar.countCSARCrash = false -- If you set to true, pilot lives count for CSAR and CSAR aircraft will count.

csar.csarOncrash = true -- If set to true, will generate CSAR even when crash

csar.autosmoke = false -- Automatically Smoke when CSAR helicopter is at 5 km

csar.allowDownedPilotCAcontrol = true -- Set to false if you don't want to allow control by Combined arms

csar.reenableIfCSARCrashes = true -- If a CSAR heli crashes, the pilots are counted as rescued anyway. Set to false to Stop this

-- - I recommend you leave the option on below IF USING MODE 1 otherwise the
-- aircraft will be disabled for the duration of the mission
csar.disableAircraftTimeout = true -- Allow aircraft to be used after 20 minutes if the pilot isnt rescued
csar.disableTimeoutTime = 10 -- Time in minutes for TIMEOUT

csar.destructionHeight = 150 -- height in meters an aircraft will be destroyed at if the aircraft is disabled

csar.enableForAI = false -- set to false to disable AI units from being rescued.

csar.weight = 100  -- Downed pilot weight when picked up

csar.enableForRED = true -- enable for red side

csar.enableForBLUE = true  -- enable for blue side

csar.enableSlotBlocking = true -- if set to true, you need to put the csarSlotBlockGameGUI.lua
-- in C:/Users/<YOUR USERNAME>/DCS/Scripts for 1.5 or C:/Users/<YOUR USERNAME>/DCS.openalpha/Scripts for 2.0
-- For missions using FLAGS and this script, the CSAR flags will NOT interfere with your mission :)

csar.bluesmokecolor = 4 -- Color of smokemarker for blue side, 0 is green, 1 is red, 2 is white, 3 is orange and 4 is blue
csar.redsmokecolor = 1 -- Color of smokemarker for red side, 0 is green, 1 is red, 2 is white, 3 is orange and 4 is blue

csar.requestdelay = 2 -- Time in seconds before the survivors will request Medevac

csar.coordtype = 3 -- Use Lat/Long DDM (0), Lat/Long DMS (1), MGRS (2), Bullseye imperial (3) or Bullseye metric (4) for coordinates.
csar.coordaccuracy = 1 -- Precision of the reported coordinates, see MIST-docs at http://wiki.hoggit.us/view/GetMGRSString
-- only applies to _non_ bullseye coords

csar.immortalcrew = true -- Set to true to make wounded crew immortal
csar.invisiblecrew = true -- Set to true to make wounded crew insvisible

csar.messageTime = 30 -- Time to show the intial wounded message for in seconds

csar.loadDistance = 60 -- configure distance for pilot to get in helicopter in meters.

csar.radioSound = "beacon.ogg" -- the name of the sound file to use for the Pilot radio beacons. If this isnt added to the mission BEACONS WONT WORK!

csar.allowFARPRescue = true --allows pilot to be rescued by landing at a FARP or Airbase

````

#### Slot Blocking

If you want to enable slot blocking, you'll need to use one of the 3 modes by changing ```csar.csarMode``` in the configuration options, set ```csar.enableSlotBlocking = true``` and copy **csarSlotBlockGameGUI.lua** to C:/Users/<YOUR USERNAME>/DCS/Scripts for 1.5 or C:/Users/<YOUR USERNAME>/DCS.openalpha/Scripts for 2.0.

The 3 modes are:
* Mode 1 - Disable the specific aircraft when it crashes or is destroyed for **All** players - Re-enabled when the pilot is rescued or after a set time
* Mode 2 - Disable the specific aircraft when it crashes or is destroyed for **The pilot that crashed / ejected** - Re-enabled when the pilot is rescued or after a set time
* Mode 3 - No specific aircraft disabling. Each pilot has a number of lives and can no longer fly when their lives are used up

Its recommended that you leave the ```csar.disableAircraftTimeout = true``` if you use Mode 1 as otherwise its possible that all aircraft in a mission could be disabled!

You can configure how long an aircraft is disabled in Mode 1 or Mode 2 by changing ```csar.disableTimeoutTime``` which will control how long until an aircraft will be disabled for in minutes.
