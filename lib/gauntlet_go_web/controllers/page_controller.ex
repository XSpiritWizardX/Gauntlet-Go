defmodule GauntletGoWeb.PageController do
  use GauntletGoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
