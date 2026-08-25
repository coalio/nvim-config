--- Credits to original theme https://github.com/marko-cerovac/material.nvim for existing
-- This is a local OLED variant of NvChad's material-darker theme.

local M = {}

M.base_30 = {
  white = "#eeffff",
  darker_black = "#000000",
  black = "#000000", -- nvim bg
  black2 = "#050505",
  one_bg = "#0a0a0a",
  one_bg2 = "#111111",
  one_bg3 = "#1a1a1a",
  grey = "#4A4A4A",
  grey_fg = "#545454",
  grey_fg2 = "#5E5E5E",
  light_grey = "#6B6B6B",
  red = "#f07178",
  baby_pink = "#FFADFF",
  pink = "#DA70CA",
  line = "#161616", -- for lines like vertsplit
  green = "#c3e88d",
  vibrant_green = "#c3e88d",
  nord_blue = "#6e98eb",
  blue = "#82aaff",
  yellow = "#ffcb6b",
  sun = "#e6b455",
  purple = "#c792ea",
  dark_purple = "#b480d6",
  teal = "#abcf76",
  orange = "#f78c6c",
  cyan = "#89ddff",
  statusline_bg = "#000000",
  lightbg = "#0f0f0f",
  selection_bg = "#242424",
  pmenu_bg = "#6e98eb",
  folder_bg = "#6e98eb",
}

M.base_16 = {
  base00 = "#000000",
  base01 = M.base_30.black2,
  base02 = M.base_30.one_bg,
  base03 = M.base_30.one_bg2,
  base04 = M.base_30.one_bg3,
  base05 = "#DFF0F0",
  base06 = "#E6F7F7",
  base07 = "#eeffff",
  base08 = "#b0bec5",
  base09 = "#f78c6c",
  base0A = "#ffcb6b",
  base0B = "#c3e88d",
  base0C = "#c3e88d",
  base0D = "#82aaff",
  base0E = M.base_30.purple,
  base0F = "#f07178",
}

M.type = "dark"

M.polish_hl = {
  defaults = {
    Visual = { bg = M.base_30.selection_bg },
    VisualNOS = { bg = M.base_30.selection_bg },
  },

  treesitter = {
    ["@attribute"] = { fg = M.base_30.purple },
    ["@conditional.ternary"] = { fg = M.base_30.cyan },
    ["@constant"] = { fg = M.base_30.yellow },
    ["@constant.builtin"] = { link = "@constant" },
    ["@constructor"] = { fg = M.base_30.cyan },
    ["@delimiter"] = { fg = M.base_30.pink },
    ["@keyword.exception"] = { fg = M.base_30.purple },
    ["@variable.member"] = { fg = M.base_30.white },
    ["@function"] = { fg = M.base_30.blue },
    ["@function.macro"] = { fg = M.base_30.cyan },
    ["@keyword"] = { fg = M.base_30.cyan },
    ["@module"] = { fg = M.base_30.yellow },
    ["@operator"] = { fg = M.base_30.cyan },
    ["@parenthesis"] = { link = "@punctuation.bracket" },
    ["@punctuation.bracket"] = { fg = M.base_30.pink },
    ["@punctuation.delimiter"] = { fg = M.base_30.pink },
    ["@keyword.repeat"] = { fg = M.base_30.purple },
    ["@string"] = { fg = M.base_30.green },
    -- ["@type"] = { fg = M.base_30.yellow },
    ["@type.qualifier"] = { fg = M.base_30.cyan },
    -- ["@variable.type"] = { fg = M.base_30.yellow },
  },

  syntax = {
    Identifier = { fg = M.base_30.white },
    Include = { fg = M.base_30.purple },
    Number = { fg = M.base_30.orange },
    Structure = { fg = M.base_30.green },
    Type = { fg = M.base_30.purple },
  },

  semantic_tokens = {
    ["@lsp.type.annotation"] = { fg = M.base_30.purple },
    ["@lsp.type.class"] = { fg = M.base_30.yellow },
    ["@lsp.type.enum"] = { link = "@lsp.type.class" },
    ["@lsp.type.enumMember"] = { link = "@lsp.type.property" },
    ["@lsp.type.interface"] = { fg = M.base_30.green, italic = true },
    ["@lsp.type.method"] = { fg = M.base_30.blue },
    ["@lsp.type.modifier"] = { fg = M.base_30.purple },
    ["@lsp.type.namespace"] = { link = "@lsp.type.class" },
    ["@lsp.type.parameter"] = { fg = M.base_30.orange },
    ["@lsp.type.property"] = { fg = M.base_30.white },
    ["@lsp.type.variable"] = { fg = M.base_30.white },
    ["@lsp.typemod.class.constructor"] = { link = "@lsp.type.method" },
    ["@lsp.typemod.record"] = { link = "@lsp.type.class" },
  },

  telescope = {
    TelescopeMatching = { fg = M.base_30.blue },
  },
}

M = require("base46").override_theme(M, "oled")

return M
