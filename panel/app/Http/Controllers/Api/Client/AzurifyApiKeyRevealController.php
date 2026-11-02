<?php

namespace Pterodactyl\Http\Controllers\Api\Client;

use Pterodactyl\Models\ApiKey;
use Illuminate\Http\JsonResponse;
use Pterodactyl\Facades\Activity;
use Illuminate\Support\Facades\Hash;
use Pterodactyl\Http\Requests\Api\Client\ClientApiRequest;

/**
 * AZURIFY: show the full secret of one of the user's own client API keys again,
 * after they confirm their account password. Every reveal is written to the activity log.
 */
class AzurifyApiKeyRevealController extends ClientApiController
{
    public function __invoke(ClientApiRequest $request, string $identifier): JsonResponse
    {
        $request->validate(['password' => 'required|string']);
        $user = $request->user();

        if (!Hash::check($request->input('password'), $user->password)) {
            return new JsonResponse([
                'errors' => [['code' => 'BadRequestHttpException', 'status' => '400', 'detail' => 'The password provided was not valid.']],
            ], 400);
        }

        /** @var ApiKey $key */
        $key = $user->apiKeys()
            ->where('key_type', ApiKey::TYPE_ACCOUNT)
            ->where('identifier', $identifier)
            ->firstOrFail();

        Activity::event('user:api-key.reveal')
            ->subject($key)
            ->property('identifier', $key->identifier)
            ->log();

        return new JsonResponse(['token' => $key->identifier . decrypt($key->token)]);
    }
}
