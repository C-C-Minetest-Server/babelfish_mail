-- babelfish_mail/init.lua
-- Translate mails into the player's preferred language
-- Copyright (C) 2024  1F616EMO
-- SPDX-License-Identifier: LGPL-3.0-or-later

local S = core.get_translator("babelfish_mail")

local mail_cache = setmetatable({}, {
    __mode = "k",
})

local function translate_mail(mail_msg, target, callback)
    local mail_cache_data = mail_cache[mail_msg]
    if not mail_cache_data then
        mail_cache_data = {}
        mail_cache[mail_msg] = mail_cache_data
    end

    mail_cache_data.translations = mail_cache_data.translations or {}
    if mail_cache_data.translations[target] and mail_cache_data.source then
        return callback(mail_cache_data.translations[target], mail_cache_data.source)
    end

    local new_body_original =
        "Subject: " .. mail_msg.subject .. "\n\n" ..
        mail_msg.body

    local specified_source = "auto"
    for _, line in ipairs(string.split(mail_msg.body, "\r?\n", false, -1, true)) do
        print(line)
        local _, _, detected = string.find(line, "^#Sourcelang: ([a-zA-Z-_]+)$")
        print(detected)
        if detected then
            detected = babelfish.validate_language(detected)
            if detected then
                specified_source = detected
                break
            end
        end
    end
    mail_cache_data.source = specified_source

    return babelfish.translate(specified_source, target, new_body_original, function(succeed, translated, source)
        if not succeed then
            return core.log("warning", string.format("Translated mail from %s to %s failed: %s",
                mail_cache_data.source or "auto", target, dump(mail_msg)))
        end
        translated =
            S("Language detected: @1", source) .. "\n" ..
            S("If this is wrong, write #Sourcelang: <language code> in your message.") .. "\n\n" ..
            translated
        mail_cache_data.source = source
        mail_cache_data.translations[target] = translated
        return callback(translated, source)
    end)
end

mail.register_on_player_receive(function(name, mail_msg)
    if string.find(mail_msg.subject, string.char(0x1b), 1, true)
        or string.find(mail_msg.body, string.char(0x1b), 1, true) then
        return
    end

    if not mail.get_setting(name, "babelfish_mail_translate") then return end

    local target = babelfish.get_player_preferred_language(name)
    if not target then return end

    return translate_mail(mail_msg, target, function(translated, source)
        if not translated or target == source then return end

        local success, err = mail.send({
            from = mail_msg.from,
            to = name,
            subject = S("Translated: @1", mail_msg.subject),
            body = translated,
        })
        if not success then
            return core.log("error", "Failed to send translated mail: %s", err)
        end
    end)
end)

local setting_index = 1
for _, def in pairs(mail.settings) do
    if def.group == "other" and def.index == setting_index then
        setting_index = setting_index + 1
    end
end
mail.settings.babelfish_mail_translate = { -- luacheck: ignore
    type = "bool",
    default = true,
    group = "other",
    index = setting_index,
    label = S("Translate incoming mails"),
    tooltip = S("Translate mails not in your preferred language.")
}
mail.selected_idxs.babelfish_mail_translate = {} -- luacheck: ignore
