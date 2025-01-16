-- babelfish_mail/init.lua
-- Translate mails into the player's preferred language
-- Copyright (C) 2024  1F616EMO
-- SPDX-License-Identifier: LGPL-3.0-or-later

local S = core.get_translator("babelfish_mail")

---@type { [table] : { [string] : string[] } }
local mail_queue = {}

local function detect_mail_language(body)
    for _, line in ipairs(string.split(body, "\r?\n", false, -1, true)) do
        local _, _, detected = string.find(line, "^#Sourcelang: ([a-zA-Z-_]+)$")
        if detected then
            detected = babelfish.validate_language(detected)
            if detected then
                return detected
            end
        end
    end
    return "auto"
end

-- Send without putting into the sender's box
local function direct_send(target, m)
    local msg = {
		id = mail.new_uuid(),
		from = m.from,
		to = m.to,
		cc = m.cc,
		bcc = m.bcc,
		subject = m.subject,
		body = m.body,
		time = os.time(),
	}
    if not core.player_exists(target) then return end

    for _, on_player_receive in ipairs(mail.registered_on_player_receives) do
        if on_player_receive(target, msg) then
            break
        end
    end

    for i=1, #mail.registered_on_receives do
		if mail.registered_on_receives[i](m) then
			break
		end
	end
end

local function do_translate(original_mail_msg, language, targets)
    local new_body_original =
        "Subject: " .. original_mail_msg.subject .. "\n\n" ..
        original_mail_msg.body
    local source_language = detect_mail_language(original_mail_msg.body)

    return babelfish.translate(source_language, language, new_body_original, function(succeed, translated, source)
        if not succeed then
            return core.log("warning", string.format("Translated mail from %s (detected: %s) to %s failed: %s",
                source_language, source, language, dump(original_mail_msg)))
        elseif language == source then
            return
        end
        translated =
            S("Language detected: @1", source) .. "\n" ..
            S("If this is wrong, write #Sourcelang: <language code> in your message.") .. "\n\n" ..
            translated

        local mail_msg = {
            from = original_mail_msg.from,
            to = original_mail_msg.to,
            cc = original_mail_msg.cc,
            bcc = original_mail_msg.bcc,
            subject = S("Translated: @1", original_mail_msg.subject),
            body = translated,
            _skip_babelfish_mail = true,
        }

        core.log("action", string.format("Translated mail from %s (detected: %s) to %s for %s: %s",
            source_language, source, language, table.concat(targets, ", "), dump(mail_msg)))

        for _, target in ipairs(targets) do
            direct_send(target, mail_msg)
        end
    end)
end

mail.register_on_player_receive(function(name, mail_msg)
    if mail_msg._skip_babelfish_mail
        or string.find(mail_msg.subject, string.char(0x1b), 1, true)
        or string.find(mail_msg.body, string.char(0x1b), 1, true) then
        return
    end

    if not mail.get_setting(name, "babelfish_mail_translate") then return end

    local target = babelfish.get_player_preferred_language(name)
    if not target then return end

    mail_queue[mail_msg] = mail_queue[mail_msg] or {}
    mail_queue[mail_msg][target] = mail_queue[mail_msg][target] or {}
    mail_queue[mail_msg][target][#mail_queue[mail_msg][target]+1] = name
end)

core.register_globalstep(function()
    local mail_msg, targets_list = next(mail_queue)
    if mail_msg then
        local language, targets = next(targets_list)
        if language then
            do_translate(mail_msg, language, targets)
            mail_queue[mail_msg][language] = nil
        else
            mail_queue[mail_msg] = nil
        end
    end
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

