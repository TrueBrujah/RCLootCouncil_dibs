local Dibs = _G.Dibs
Dibs.EncounterJournal = Dibs.EncounterJournal or {}

function Dibs.EncounterJournal.AddActionIfAvailable()
  if not EncounterJournal then
    return false
  end

  Dibs.EncounterJournal.actionInstalled = true
  return true
end

function Dibs.EncounterJournal.BuildActionLabel()
  return "I want to DIB this"
end

function Dibs.EncounterJournal.CanPreDib(itemID)
  return type(itemID) == "number" and itemID > 0
end
