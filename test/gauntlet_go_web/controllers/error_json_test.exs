defmodule GauntletGoWeb.ErrorJSONTest do
  use GauntletGoWeb.ConnCase, async: true

  test "renders 404" do
    assert GauntletGoWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert GauntletGoWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
