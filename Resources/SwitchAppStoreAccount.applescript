-- Credentials are injected in memory by StoreSwitch. Never log these variables.
property targetEmail : "__STORE_SWITCH_APPLE_ID__"
property targetPassword : "__STORE_SWITCH_PASSWORD__"

on localeIsChinese()
	set lang to ""
	try
		set lang to do shell script "defaults read -g AppleLanguages 2>/dev/null | sed -n '2{s/[\" ,]//g;p;}'"
	end try
	if lang is "" then
		try
			set lang to do shell script "defaults read -g AppleLocale 2>/dev/null"
		end try
	end if
	if lang is "" then
		try
			set lang to user locale of (system info)
		end try
	end if
	return lang starts with "zh"
end localeIsChinese

on localeMenuNames()
	if my localeIsChinese() then
		return {"商店", "登录", "退出登录"}
	else
		return {"Store", "Sign In", "Sign Out"}
	end if
end localeMenuNames

on localizedText(chineseText, englishText)
	if my localeIsChinese() then return chineseText
	return englishText
end localizedText

on ensureFront()
	tell application "App Store" to activate
	tell application "System Events" to tell process "App Store"
		try
			set frontmost to true
		end try
	end tell
end ensureFront

on findSheet()
	-- The sign-in sheet is usually on window 1, but search every window to be safe.
	tell application "System Events" to tell process "App Store"
		try
			repeat with w in windows
				if (count of sheets of w) > 0 then return sheet 1 of w
			end repeat
		end try
	end tell
	return missing value
end findSheet

on probeSheet()
	-- Returns {sheetVisible, appleIDField, passwordField}. Fields are missing value when absent.
	-- Newer macOS nests the fields several levels deep, so walk the whole sheet.
	set sh to my findSheet()
	if sh is missing value then return {false, missing value, missing value}
	set idField to missing value
	set secField to missing value
	tell application "System Events"
		try
			set els to entire contents of sh
		on error
			return {true, missing value, missing value}
		end try
		repeat with e in els
			set e to contents of e
			set r to ""
			try
				set r to role of e as text
			end try
			if r is in {"AXTextField", "AXComboBox", "AXTextArea", "AXSecureTextField"} then
				-- AXSubrole is stable across locales; the description is localized.
				set isSecureField to (r is "AXSecureTextField")
				if not isSecureField then
					try
						if (subrole of e as text) is "AXSecureTextField" then set isSecureField to true
					end try
				end if
				if not isSecureField then
					try
						if (description of e as text) is in {"secure text field", "安全文本栏"} then set isSecureField to true
					end try
				end if
				if isSecureField then
					if secField is missing value then set secField to e
				else
					if idField is missing value then set idField to e
				end if
			end if
		end repeat
	end tell
	return {true, idField, secField}
end probeSheet

on describeSheet()
	-- Diagnostic only: control roles, never values or titles.
	set sh to my findSheet()
	if sh is missing value then return "no sheet"
	set parts to {}
	tell application "System Events"
		try
			set els to entire contents of sh
			set n to 0
			repeat with e in els
				set n to n + 1
				if n > 60 then exit repeat
				set e to contents of e
				set r to "?"
				set sr to ""
				try
					set r to role of e as text
				end try
				try
					set sr to subrole of e as text
				end try
				if sr is not "" and sr is not "missing value" then set r to r & "/" & sr
				set end of parts to r
			end repeat
		on error errMsg
			return "describe failed: " & errMsg
		end try
	end tell
	set AppleScript's text item delimiters to ", "
	set out to parts as text
	set AppleScript's text item delimiters to ""
	return out
end describeSheet

on typeInField(tf, txt, doSelectAll, shouldSubmit)
	my ensureFront()
	tell application "System Events"
		try
			set focused of tf to true
		end try
		delay 0.2
		try
			if not (focused of tf) then click tf
		end try
		delay 0.3
		tell process "App Store"
			if doSelectAll then
				keystroke "a" using command down
				delay 0.2
			end if
			keystroke txt
			delay 0.3
			if shouldSubmit then
				key code 36
				delay 0.3
			end if
		end tell
	end tell
end typeInField

on run
	tell application "App Store" to activate
	delay 1.5

	set menuNames to my localeMenuNames()
	set storeName to item 1 of menuNames
	set signInName to item 2 of menuNames
	set signOutName to item 3 of menuNames
	set signInCandidates to {signInName, signInName & "…", signInName & "..."}
	set signOutCandidates to {signOutName, signOutName & "…", signOutName & "..."}

	my ensureFront()
	delay 1.5
	tell application "System Events" to tell process "App Store"
		repeat 3 times
			if (count of sheets of window 1) is 0 then exit repeat
			key code 53
			delay 0.5
		end repeat

		set storeMenu to missing value
		repeat with menuBarItem in menu bar items of menu bar 1
			if (name of menuBarItem) is storeName then
				set storeMenu to menuBarItem
				exit repeat
			end if
		end repeat
		if storeMenu is missing value then error (my localizedText("找不到 App Store 的“" & storeName & "”菜单。", "Could not find the App Store “" & storeName & "” menu."))

		click storeMenu
		delay 0.5
		set didSignOut to false
		repeat with candidate in signOutCandidates
			try
				click menu item candidate of menu 1 of storeMenu
				set didSignOut to true
				exit repeat
			end try
		end repeat
		if didSignOut then
			delay 2
		else
			key code 53
		end if

		delay 0.5
		click storeMenu
		delay 0.5
		set clickedSignIn to false
		repeat with candidate in signInCandidates
			try
				click menu item candidate of menu 1 of storeMenu
				set clickedSignIn to true
				exit repeat
			end try
		end repeat
		if not clickedSignIn then
			key code 53
			error (my localizedText("找不到 App Store 的登录菜单项。", "Could not find the App Store sign-in menu item."))
		end if
	end tell

	set probe to {false, missing value, missing value}
	repeat 20 times
		delay 0.5
		set probe to my probeSheet()
		if item 1 of probe then exit repeat
	end repeat
	if not (item 1 of probe) then error (my localizedText("App Store 登录窗口没有出现。", "The App Store sign-in window did not appear."))

	-- Wait for the sheet's content to finish loading.
	repeat 20 times
		set probe to my probeSheet()
		if (item 2 of probe is not missing value) or (item 3 of probe is not missing value) then exit repeat
		delay 0.5
	end repeat

	set idField to item 2 of probe
	set secField to item 3 of probe
	if idField is not missing value then
		if secField is missing value then
			my typeInField(idField, targetEmail, true, true)
			repeat 20 times
				delay 0.5
				set probe to my probeSheet()
				if (item 1 of probe) and (item 3 of probe is not missing value) then exit repeat
			end repeat
			if not ((item 1 of probe) and (item 3 of probe is not missing value)) then error (my localizedText("提交 Apple ID 后没有识别到密码框。", "The password field was not detected after submitting the Apple ID.") & " [" & my describeSheet() & "]")
		else
			my typeInField(idField, targetEmail, true, false)
			set probe to my probeSheet()
		end if
	end if

	set secField to item 3 of probe
	if secField is missing value then error (my localizedText("没有识别到 App Store 密码框。", "The App Store password field was not detected.") & " [" & my describeSheet() & "]")
	my typeInField(secField, targetPassword, false, true)

	repeat 40 times
		delay 0.5
		set probe to my probeSheet()
		if not (item 1 of probe) then return "completed"
	end repeat
	return "needs_attention"
end run
