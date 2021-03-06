defmodule SocketTranslatorPhx.YandexTranslator do
  alias SocketTranslatorPhx.Workers.TokenWorker
  alias SocketTranslatorPhx.Workers.CacheWorker

  require Logger

  @spec translate_message(String.t()) :: String.t() | {:error, atom()}
  def translate_message(message) do
    Logger.info("Translating #{message} to en")

    case CacheWorker.get_translated_message_from_cache(message) do
      nil -> post_request_to_yandex_translator(message)
      translated_message -> translated_message
    end
  end

  defp post_request_to_yandex_translator(message) do
    token = TokenWorker.get_token()

    headers = [{"Content-Type", "application/json"}, {"Authorization", "Bearer #{token}"}]

    folder_id = get_folder_id()
    body =
      %{
        folder_id: folder_id,
        texts: message,
        targetLanguageCode: "en"
      }
      |> Jason.encode!()

    api_url = get_api_url()

    case HTTPoison.post(api_url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200} = response} ->
        parse_response(response)

      {:ok, %HTTPoison.Response{status_code: 400} = response} ->
        parse_error(response)

      {:ok, %HTTPoison.Response{status_code: 500} = response} ->
        parse_error(response)

      {:error, %HTTPoison.Error{} = error} ->
        parse_error(error)
    end
  end

  @spec parse_response(HTTPoison.Response.t()) :: String.t()
  defp parse_response(%HTTPoison.Response{body: body}) do
    result = Jason.decode!(body)

    %{"translations" => translations} = result

    translations
    |> Enum.reduce("", fn %{"text" => text}, acc -> acc <> text <> " " end)
    |> String.trim()
  end

  @spec parse_error(HTTPoison.Error.t() | HTTPoison.Response.t()) :: {:error, atom()}
  defp parse_error(%HTTPoison.Error{reason: reason}), do: {:error, reason}

  defp parse_error(%HTTPoison.Response{status_code: 400}), do: {:error, :bad_request}

  defp parse_error(%HTTPoison.Response{status_code: 500}), do: {:error, :internal_server_error}

  @spec get_api_url() :: String.t()
  defp get_api_url(), do: Application.get_env(:socket_translator_phx, __MODULE__)[:api_url]

  @spec get_folder_id() :: String.t()
  defp get_folder_id(), do: Application.get_env(:socket_translator_phx, __MODULE__)[:folder_id]
end
