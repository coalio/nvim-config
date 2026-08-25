-- Credits to original https://github.com/morhetz/gruvbox
-- This variant preserves Gruvbox accents over near-OLED dark gray surfaces.

local M = {}

M.base_30 = {
  white = "#ebdbb2",
  darker_black = "#090909",
  black = "#0c0c0c", -- nvim bg
  black2 = "#111111",
  one_bg = "#171717",
  one_bg2 = "#1d1d1d",
  one_bg3 = "#242424",
  grey = "#3a3a3a",
  grey_fg = "#454545",
  grey_fg2 = "#505050",
  light_grey = "#656565",
  red = "#fb4934",
  baby_pink = "#cc241d",
  pink = "#ff75a0",
  line = "#242424", -- for lines like vertsplit
  green = "#b8bb26",
  vibrant_green = "#a9b665",
  nord_blue = "#83a598",
  blue = "#458588",
  yellow = "#d79921",
  sun = "#fabd2f",
  purple = "#b4bbc8",
  dark_purple = "#d3869b",
  teal = "#749689",
  orange = "#e78a4e",
  cyan = "#82b3a8",
  statusline_bg = "#101010",
  lightbg = "#202020",
  pmenu_bg = "#83a598",
  folder_bg = "#749689",
}

M.base_16 = {
  base00 = M.base_30.black,
  base01 = M.base_30.black2,
  base02 = M.base_30.one_bg3,
  base03 = "#303030",
  base04 = "#bdae93",
  base05 = "#d5c4a1",
  base06 = M.base_30.white,
  base07 = "#fbf1c7",
  base08 = M.base_30.red,
  base09 = "#fe8019",
  base0A = M.base_30.sun,
  base0B = M.base_30.green,
  base0C = "#8ec07c",
  base0D = M.base_30.nord_blue,
  base0E = M.base_30.dark_purple,
  base0F = "#d65d0e",
}

M.type = "dark"

M = require("base46").override_theme(M, "gruvbox-darker")

M.polish_hl = {
  syntax = {
    Operator = { fg = M.base_30.nord_blue },
  },

  treesitter = {
    ["@operator"] = { fg = M.base_30.nord_blue },
  },
}

return M
