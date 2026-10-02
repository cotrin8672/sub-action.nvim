local M = {}

function M.request(s, callback)
	if #vim.lsp.get_clients({ bufnr = s.bufnr, method = "textDocument/codeAction" }) == 0 then
		callback({})
		return function() end
	end
	local parameters = {}
	return vim.lsp.buf_request_all(s.bufnr, "textDocument/codeAction", function(client)
		local params = vim.lsp.util.make_range_params(s.winid, client.offset_encoding)
		local diagnostics = {}
		for _, pull in ipairs({ false, true }) do
			local namespace = vim.lsp.diagnostic.get_namespace(client.id, pull)
			for _, diagnostic in ipairs(vim.diagnostic.get(s.bufnr, { namespace = namespace, lnum = s.cursor[1] - 1 })) do
				if diagnostic.user_data and diagnostic.user_data.lsp then
					diagnostics[#diagnostics + 1] = diagnostic.user_data.lsp
				end
			end
		end
		params.context = { diagnostics = diagnostics, triggerKind = 1 }
		parameters[client.id] = params
		return params
	end, function(results)
		local entries = {}
		local ids = vim.tbl_keys(results)
		table.sort(ids)
		for _, id in ipairs(ids) do
			local client, response = vim.lsp.get_client_by_id(id), results[id]
			if response.error then
				vim.notify("sub-action: " .. (response.error.message or tostring(response.error)), vim.log.levels.WARN)
			elseif client then
				for _, action in ipairs(response.result or {}) do
					if type(action.title) == "string" then
						entries[#entries + 1] = { action = action, client = client, params = parameters[id] }
					end
				end
			end
		end
		callback(entries)
	end)
end

function M.resolve(entry, bufnr, callback, for_apply)
	local action, client = entry.action, entry.client
	if entry.resolved then
		callback(entry.resolved, entry.resolve_error)
		return
	end
	if
		type(action.command) == "string"
		or (action.edit and (not for_apply or action.command))
		or not client:supports_method("codeAction/resolve", bufnr)
		or action.disabled
	then
		callback(action)
		return
	end
	if entry.waiters then
		entry.waiters[#entry.waiters + 1] = callback
		return
	end
	entry.waiters = { callback }
	local function finish(err, resolved)
		entry.request_id = nil
		entry.resolved, entry.resolve_error = resolved or action, err
		local waiters = entry.waiters
		entry.waiters = nil
		for _, waiter in ipairs(waiters) do
			waiter(entry.resolved, err)
		end
	end
	local sent, id = client:request("codeAction/resolve", action, function(err, resolved)
		vim.schedule(function()
			finish(err, resolved)
		end)
	end, bufnr)
	entry.request_id = id
	if not sent then
		finish({ message = "Language server could not resolve this action" })
	end
end

function M.apply(entry, action, bufnr, callback)
	if action.disabled then
		callback({ message = action.disabled.reason or "Action is disabled" })
		return
	end
	local ok, err = pcall(function()
		if action.edit then
			vim.lsp.util.apply_workspace_edit(action.edit, entry.client.offset_encoding)
		end
		local command = type(action.command) == "string" and action or action.command
		if command then
			local local_handler = entry.client.commands[command.command] or vim.lsp.commands[command.command]
			entry.client:exec_cmd(
				command,
				{ bufnr = bufnr, method = "textDocument/codeAction", params = entry.params },
				callback
			)
			if local_handler then
				callback()
			end
		elseif action.edit then
			callback()
		else
			callback({ message = "Action has no edit or command" })
		end
	end)
	if not ok then
		callback({ message = tostring(err) })
	end
end

function M.preview(edit, encoding)
	if not edit then
		return { "Preview unavailable" }
	end
	local documents, order, operations = {}, {}, {}
	local scratch = {}
	local function name(uri)
		return vim.fn.fnamemodify(vim.uri_to_fname(uri), ":~:.")
	end
	local function document(uri, initial)
		if documents[uri] then
			return documents[uri]
		end
		local lines = initial
		if not lines then
			local filename = vim.uri_to_fname(uri)
			local buffer = vim.fn.bufnr(filename)
			if buffer ~= -1 and vim.api.nvim_buf_is_loaded(buffer) then
				lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
			else
				lines = vim.fn.readfile(filename)
			end
		end
		local buffer = vim.api.nvim_create_buf(false, true)
		scratch[#scratch + 1] = buffer
		vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
		local doc = { before = table.concat(lines, "\n") .. "\n", buffer = buffer }
		documents[uri], order[#order + 1] = doc, uri
		return doc
	end
	local function apply(uri, edits)
		local doc = document(uri)
		local copy = vim.deepcopy(edits)
		-- Annotations belong to apply, never to a read-only preview.
		for _, text_edit in ipairs(copy) do
			text_edit.annotationId = nil
		end
		vim.lsp.util.apply_text_edits(copy, doc.buffer, encoding)
	end
	local ok, result = pcall(function()
		if edit.documentChanges then
			for _, change in ipairs(edit.documentChanges) do
				if change.kind == "create" then
					operations[#operations + 1] = "Create " .. name(change.uri)
					document(change.uri, { "" })
				elseif change.kind == "rename" then
					operations[#operations + 1] = "Rename " .. name(change.oldUri) .. " → " .. name(change.newUri)
					local doc = document(change.oldUri)
					documents[change.newUri] = doc
				elseif change.kind == "delete" then
					operations[#operations + 1] = "Delete " .. name(change.uri)
				elseif change.textDocument then
					apply(change.textDocument.uri, change.edits)
				end
			end
		else
			local uris = vim.tbl_keys(edit.changes or {})
			table.sort(uris)
			for _, uri in ipairs(uris) do
				apply(uri, edit.changes[uri])
			end
		end
		local lines = vim.list_extend({}, operations)
		for _, uri in ipairs(order) do
			local doc = documents[uri]
			local after = table.concat(vim.api.nvim_buf_get_lines(doc.buffer, 0, -1, false), "\n") .. "\n"
			local diff = vim.diff(doc.before, after, { result_type = "unified", ctxlen = 3 })
			if diff ~= "" then
				if #lines > 0 then
					lines[#lines + 1] = ""
				end
				lines[#lines + 1], lines[#lines + 2] = "--- " .. name(uri), "+++ " .. name(uri)
				vim.list_extend(lines, vim.split(diff, "\n", { trimempty = true }))
			end
		end
		return #lines > 0 and lines or { "No text changes" }
	end)
	for _, buffer in ipairs(scratch) do
		vim.api.nvim_buf_delete(buffer, { force = true })
	end
	if not ok then
		error(result)
	end
	return result
end

return M
