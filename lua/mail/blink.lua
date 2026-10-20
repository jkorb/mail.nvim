local M = {}
local installed

function M.reset()
  local config = package.loaded["blink.cmp.config"]
  if installed and config and config.sources.per_filetype.mail == installed.select then
    config.sources.per_filetype.mail = installed.previous
  end
  if installed then
    vim.api.nvim_del_augroup_by_id(installed.group)
  end
  installed = nil
end

function M.configure(contacts)
  -- Wait for Blink's own setup; requiring it here can interfere with lazy loading.
  local config = package.loaded["blink.cmp.config"]
  if not config then
    return
  end
  local per_filetype = config.sources.per_filetype
  if installed and per_filetype.mail == installed.select then
    return
  end

  -- The provider ID may differ from the nvim-cmp source name (e.g. "contacts").
  local ids = {}
  for id, provider in pairs(config.sources.providers) do
    local name = (provider.opts and provider.opts.cmp_name) or provider.name
    if provider.module == "blink.compat.source" and name == "cmp-contacts" then
      ids[#ids + 1] = id
    end
  end
  if #ids == 0 then
    return
  end
  table.sort(ids)
  local id = vim.tbl_contains(ids, "cmp-contacts") and "cmp-contacts" or ids[1]
  local previous = per_filetype.mail
  local function select_sources()
    if contacts:is_exclusive() then
      return { id }
    end
    if type(previous) == "function" then
      return previous()
    end
    return previous or { inherit_defaults = true }
  end
  local group = vim.api.nvim_create_augroup("mail_nvim_blink", { clear = true })
  local current = { previous = previous, select = select_sources, group = group }
  installed = current
  per_filetype.mail = select_sources

  -- Blink reuses a context's providers while typing. Refresh the list when a
  -- paste, deletion or cursor movement crosses into/out of contact completion.
  local pending = false
  vim.api.nvim_create_autocmd({ "TextChangedI", "CursorMovedI" }, {
    group = group,
    callback = function(event)
      if pending or vim.bo[event.buf].filetype ~= "mail" then
        return
      end
      pending = true
      vim.schedule(function()
        pending = false
        if installed ~= current or vim.api.nvim_get_current_buf() ~= event.buf
          or vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i"
          or per_filetype.mail ~= select_sources then
          return
        end
        local trigger = package.loaded["blink.cmp.completion.trigger"]
        local context = trigger and trigger.context
        local sources = package.loaded["blink.cmp.sources.lib"]
        local blink = package.loaded["blink.cmp"]
        if not context or context.bufnr ~= event.buf or context.trigger.kind == "prefetch"
          or not sources or not blink then
          return
        end
        if not contacts:is_exclusive() and not vim.deep_equal(context.providers, { id }) then
          return
        end
        local providers = sources.get_enabled_provider_ids("default")
        if not vim.deep_equal(context.providers, providers) then
          blink.show({ providers = providers })
        end
      end)
    end,
  })
end

return M
