--[[ 
    ===================================
                SETTINGS
    ===================================
  ]]
local function InvertBooleanSetting(settings, oldSetting, newSetting)
    if settings[oldSetting] == nil then 
        return
    end
    settings[newSetting] = not settings[oldSetting]
    settings[oldSetting] = nil
end
local function UpgradeSettings(settings)
    if not settings.dataVersion then
        settings.dataVersion = 2
        InvertBooleanSetting(settings, "skipEmptySystemMail", "systemDeleteEmpty")
        InvertBooleanSetting(settings, "skipEmptyPlayerMail", "playerDeleteEmpty")
        InvertBooleanSetting(settings, "skipOtherPlayerMail", "playerTakeAttached")
        InvertBooleanSetting(settings, "skipCod", "codTake")
    end
end
function Postmaster:SettingsSetup()

    self.defaults = {
        bounce = false,
        codTake = false,
        codGoldLimit = 10000,
        codMasterMerchantMinDeal = ITEM_QUALITY_NORMAL,
        codTakeWithNoMasterMerchantData = false,
        deleteDialogSuppress = false,
        playerDeleteBulk = false,
        playerDeleteEmpty = false,
        playerDeleteEmptyFilter = "",
        playerTakeAttached = true,
        reservedSlots = 0,
        systemDeleteEmpty = false,
        systemDeleteEmptyFilter = GetString(SI_PM_CHAMPION_160_REWARD),
        systemTakeAttached = true,
        systemTakeGuildStore = true,
        systemTakeHireling = true,
        systemTakeOther = true,
        systemTakePvp = true,
        systemTakeUndaunted = true,
        verbose = true,
        verboseCombine = false,
    }
    
    -- Initialize saved variable
    self.settings = ZO_SavedVars:NewAccountWide("Postmaster_Data", 1, nil, self.defaults)
    
    UpgradeSettings(self.settings)
    
    local LAM2 = LibStub("LibAddonMenu-2.0")
    if not LAM2 then return end
    
    local panelData = {
        type = "panel",
        name = Postmaster.title,
        displayName = ZO_HIGHLIGHT_TEXT:Colorize(Postmaster.title),
        author = Postmaster.author,
        version = Postmaster.version,
        registerForRefresh = true,
        registerForDefaults = true,
    }
    self.settingsPanel = LAM2:RegisterAddonPanel(Postmaster.name .. "Options", panelData)
    
    local optionsTable = {
        {
            type = "description",
            text = GetString(SI_PM_HELP_01),
            width = "full"
        },
        {
            type = "description",
            text = GetString(SI_PM_HELP_04),
            width = "full"
        },
        {
            type = "description",
            text = GetString(SI_PM_HELP_02),
            width = "full"
        },
        {
            type = "description",
            text = GetString(SI_PM_HELP_03),
            width = "full"
        },
        {
            type = "header",
            name = GetString(SI_LOOT_TAKE_ALL),
            width = "full"
        },
        -- Reserved slots
        {
            type = "slider",
            name = GetString(SI_PM_RESERVED_SLOTS),
            tooltip = GetString(SI_PM_RESERVED_SLOTS_TOOLTIP),
            getFunc = function() return self.settings.reservedSlots end,
            setFunc = function(value) self.settings.reservedSlots = value end,
            min = 0,
            max = 200,
            step = 1,
            clampInput = true,
            width = "full",
            default = self.defaults.reservedSlots,
        },
        -- Delete MailR and GodSend bulk mail
        {
            type = "checkbox",
            name = GetString(SI_PM_PLAYER_DELETE_BULK),
            getFunc = function() return self.settings.playerDeleteBulk end,
            setFunc = function(value) self.settings.playerDeleteBulk = value end,
            width = "full",
            default = self.defaults.playerDeleteBulk,
        },
        -- divider
        --{ type = "divider", width = "full" },
        
        
        --[ SYSTEM ]--
        { type = "submenu", name = GetString(SI_PM_SYSTEM), controls = {
        
        -- System mail with attachments
        {
            type = "checkbox",
            name = GetString(SI_PM_SYSTEM_TAKE_ATTACHED),
            tooltip = GetString(SI_PM_SYSTEM_TAKE_ATTACHED_TOOLTIP),
            getFunc = function() return self.settings.systemTakeAttached end,
            setFunc = function(value) self.settings.systemTakeAttached = value end,
            width = "full",
            default = self.defaults.systemTakeAttached,
        },
        -- PvP mail
        {
            type = "checkbox",
            name = GetString(SI_PM_SYSTEM_TAKE_PVP),
            getFunc = function() return self.settings.systemTakePvp end,
            setFunc = function(value) self.settings.systemTakePvp = value end,
            width = "full",
            disabled = function() return not self.settings.systemTakeAttached end,
            default = self.defaults.systemTakePvp,
        },
        
        -- Hireling mail
        {
            type = "checkbox",
            name = GetString(SI_PM_SYSTEM_TAKE_CRAFTING),
            getFunc = function() return self.settings.systemTakeHireling end,
            setFunc = function(value) self.settings.systemTakeHireling = value end,
            width = "full",
            disabled = function() return not self.settings.systemTakeAttached end,
            default = self.defaults.systemTakeHireling,
        },
        
        -- Guild store mail
        {
            type = "checkbox",
            name = GetString(SI_WINDOW_TITLE_TRADING_HOUSE),
            getFunc = function() return self.settings.systemTakeGuildStore end,
            setFunc = function(value) self.settings.systemTakeGuildStore = value end,
            width = "full",
            disabled = function() return not self.settings.systemTakeAttached end,
            default = self.defaults.systemTakeGuildStore,
        },
        
        -- Undaunted mail
        {
            type = "checkbox",
            name = GetString(SI_PM_SYSTEM_TAKE_UNDAUNTED), 
            getFunc = function() return self.settings.systemTakeUndaunted end,
            setFunc = function(value) self.settings.systemTakeUndaunted = value end,
            width = "full",
            disabled = function() return not self.settings.systemTakeAttached end,
            default = self.defaults.systemTakeUndaunted,
        },
        -- Other system attachments
        {
            type = "checkbox",
            name = GetString(SI_PM_SYSTEM_TAKE_OTHER),
            getFunc = function() return self.settings.systemTakeOther end,
            setFunc = function(value) self.settings.systemTakeOther = value end,
            width = "full",
            disabled = function() return not self.settings.systemTakeAttached end,
            default = self.defaults.systemTakeOther,
        },
        -- divider
        { type = "divider", width = "full" },
        -- System mail without attachments
        {
            type = "checkbox",
            name = GetString(SI_PM_SYSTEM_DELETE_EMPTY),
            tooltip = GetString(SI_PM_SYSTEM_DELETE_EMPTY_TOOLTIP),
            getFunc = function() return self.settings.systemDeleteEmpty end,
            setFunc = function(value) self.settings.systemDeleteEmpty = value end,
            width = "full",
            default = self.defaults.systemDeleteEmpty,
        },
        -- Empty system mail filter
        {
            type = "editbox",
            name = GetString(SI_PM_SYSTEM_DELETE_EMPTY_FILTER),
            tooltip = GetString(SI_PM_SYSTEM_DELETE_EMPTY_FILTER_TOOLTIP),
            getFunc = function() return self.settings.systemDeleteEmptyFilter end,
            setFunc = function(value) self.settings.systemDeleteEmptyFilter = value end,
            width = "full",
            disabled = function() return not self.settings.systemDeleteEmpty end,
            default = self.defaults.systemDeleteEmptyFilter,
        },
        }},
        
        -- divider
        --{ type = "divider", width = "full" },
        -- Player mail with attachments
        
        --[ PLAYER ]--
        { type = "submenu", name = GetString(SI_PM_PLAYER), controls = {
        
        {
            type = "checkbox",
            name = GetString(SI_PM_PLAYER_TAKE_ATTACHED),
            tooltip = GetString(SI_PM_PLAYER_TAKE_ATTACHED_TOOLTIP),
            getFunc = function() return self.settings.playerTakeAttached end,
            setFunc = function(value) self.settings.playerTakeAttached = value end,
            width = "full",
            default = self.defaults.playerTakeAttached,
        },
        -- divider
        { type = "divider", width = "full" },
        -- Player mail without attachments
        {
            type = "checkbox",
            name = GetString(SI_PM_PLAYER_DELETE_EMPTY),
            tooltip = GetString(SI_PM_PLAYER_DELETE_EMPTY_TOOLTIP),
            getFunc = function() return self.settings.playerDeleteEmpty end,
            setFunc = function(value) self.settings.playerDeleteEmpty = value end,
            width = "full",
            default = self.defaults.playerDeleteEmpty,
        },
        -- Empty player mail filter
        {
            type = "editbox",
            name = GetString(SI_PM_PLAYER_DELETE_EMPTY_FILTER),
            tooltip = GetString(SI_PM_PLAYER_DELETE_EMPTY_FILTER_TOOLTIP),
            getFunc = function() return self.settings.playerDeleteEmptyFilter end,
            setFunc = function(value) self.settings.playerDeleteEmptyFilter = value end,
            width = "full",
            disabled = function() return not self.settings.playerDeleteEmpty end,
            default = self.defaults.playerDeleteEmptyFilter,
        },
        }},
        
        -- divider
        --{ type = "divider", width = "full" },
        
        --[ COD ]--
        { type = "submenu", name = GetString(SI_MAIL_SEND_COD), controls = {
        -- Take COD mail
        {
            type = "checkbox",
            name = GetString(SI_PM_COD),
            tooltip = GetString(SI_PM_COD_TOOLTIP),
            getFunc = function() return self.settings.codTake end,
            setFunc = function(value) self.settings.codTake = value end,
            width = "full",
            default = self.defaults.codTake,
        },
        -- Absolute COD gold limit
        {
            type = "slider",
            name = GetString(SI_PM_COD_LIMIT),
            tooltip = GetString(SI_PM_COD_LIMIT_TOOLTIP),
            getFunc = function() return self.settings.codGoldLimit end,
            setFunc = function(value) self.settings.codGoldLimit = value end,
            min = 0,
            max = 200000,
            width = "full", 
            clampInput = false,
            disabled = function() return not self.settings.codTake end,
            default = self.defaults.codGoldLimit,
        },
        -- Master Merchant deal limit
        {
            type = "masterMerchantDealSlider",
            name = GetString(SI_PM_COD_MM_MIN_DEAL),
            tooltip = GetString(SI_PM_COD_MM_MIN_DEAL_TOOLTIP),
            getFunc = function() return self.settings.codMasterMerchantMinDeal end,
            setFunc = function(value) self.settings.codMasterMerchantMinDeal = value end,
            width = "full", 
            disabled = function() return not self.settings.codTake end,
            default = self.defaults.codMasterMerchantMinDeal,
        },
        -- Take attachments with no Master Merchant data
        {
            type = "checkbox",
            name = GetString(SI_PM_COD_MM_NO_DATA),
            tooltip = GetString(SI_PM_COD_MM_NO_DATA_TOOLTIP),
            getFunc = function() return MasterMerchant ~= nil and self.settings.codTakeWithNoMasterMerchantData end,
            setFunc = function(value) self.settings.codTakeWithNoMasterMerchantData = value end,
            width = "full",
            disabled = function() return not self.settings.codTake or not MasterMerchant end,
            warning = not MasterMerchant and GetString(SI_PM_MASTER_MERCHANT_WARNING),
            default = self.defaults.codTakeWithNoMasterMerchantData,
        },
        }},
        
        --[ OPTIONS ]--
        
        -- spacer
        { type = "description", width = "full" },
        -- header
        {
            type = "header",
            name = GetString(SI_GAMEPAD_OPTIONS_MENU),
            width = "full"
        },
        -- Verbose option
        {
            type = "checkbox",
            name = GetString(SI_PM_VERBOSE),
            tooltip = GetString(SI_PM_VERBOSE_TOOLTIP),
            getFunc = function() return self.settings.verbose end,
            setFunc = function(value) self.settings.verbose = value end,
            width = "full",
            default = self.defaults.verbose,
        },
        -- Verbose combine option
        {
            type = "checkbox",
            name = GetString(SI_PM_VERBOSE_COMBINE),
            tooltip = GetString(SI_PM_VERBOSE_COMBINE_TOOLTIP),
            getFunc = function() return self.settings.verboseCombine end,
            setFunc = function(value) self.settings.verboseCombine = value end,
            width = "full",
            default = self.defaults.verboseCombine,
            disable = not self.settings.verbose,
        },
        -- Delete confirmation dialog suppression
        {
            type = "checkbox",
            name = GetString(SI_PM_DELETE_DIALOG_SUPPRESS),
            tooltip = GetString(SI_PM_DELETE_DIALOG_SUPPRESS_TOOLTIP),
            getFunc = function() return self.settings.deleteDialogSuppress end,
            setFunc = function(value) self.settings.deleteDialogSuppress = value end,
            width = "full",
            default = self.defaults.deleteDialogSuppress,
        },
        -- Bounce mail option
        {
            type = "checkbox",
            name = GetString(SI_PM_BOUNCE),
            tooltip = GetString(SI_PM_BOUNCE_TOOLTIP),
            getFunc = function() return self.settings.bounce and not (WYK_MailBox and WYK_MailBox.Settings.Enabled) end,
            setFunc = function(value) self.settings.bounce = value end,
            width = "full",
            default = self.defaults.bounce,
            disabled = function() return WYK_MailBox and WYK_MailBox.Settings.Enabled end,
            warning = not WYK_MailBox or 
                function() 
                    if WYK_MailBox.Settings.Enabled then
                        return GetString(SI_PM_WYKKYD_MAILBOX_RETURN_WARNING)
                    else
                        return GetString(SI_PM_WYKKYD_MAILBOX_DETECTED_WARNING)
                    end
                end
        }
    }
        
    LAM2:RegisterOptionControls(Postmaster.name .. "Options", optionsTable)
    
    SLASH_COMMANDS["/postmaster"] = self.OpenSettingsPanel
    SLASH_COMMANDS["/pm"] = self.OpenSettingsPanel
end