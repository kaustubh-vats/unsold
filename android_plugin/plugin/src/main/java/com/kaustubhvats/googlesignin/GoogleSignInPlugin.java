package com.kaustubhvats.googlesignin;

import android.app.Activity;
import android.content.Intent;
import android.os.CancellationSignal;

import androidx.annotation.NonNull;
import android.os.Handler;
import android.os.Looper;
import androidx.credentials.ClearCredentialStateRequest;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.ClearCredentialException;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException;
import androidx.credentials.exceptions.GetCredentialUnsupportedException;

import com.google.android.gms.auth.api.signin.GoogleSignIn;
import com.google.android.gms.auth.api.signin.GoogleSignInAccount;
import com.google.android.gms.auth.api.signin.GoogleSignInClient;
import com.google.android.gms.auth.api.signin.GoogleSignInOptions;
import com.google.android.gms.common.api.ApiException;

import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.Executor;

/**
 * Minimal Godot Android plugin: native "Sign in with Google" via Credential Manager.
 * Emits an ID token which the game exchanges for a Firebase session (signInWithIdp).
 */
public class GoogleSignInPlugin extends GodotPlugin {

    private static Executor mainExecutor() {
        Handler handler = new Handler(Looper.getMainLooper());
        return handler::post;
    }

    public GoogleSignInPlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "GoogleSignIn";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("sign_in_success", String.class, String.class, String.class));
        signals.add(new SignalInfo("sign_in_failed", String.class));
        return signals;
    }

    /** Shows the Google account picker. webClientId is the OAuth "Web client ID" from Firebase. */
    @UsedByGodot
    public void signIn(String webClientId) {
        final Activity activity = getActivity();
        if (activity == null) {
            emitSignal("sign_in_failed", "No activity");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                GetSignInWithGoogleOption option = new GetSignInWithGoogleOption.Builder(webClientId).build();
                GetCredentialRequest request = new GetCredentialRequest.Builder()
                        .addCredentialOption(option)
                        .build();
                CredentialManager manager = CredentialManager.create(activity);
                manager.getCredentialAsync(activity, request, new CancellationSignal(),
                        mainExecutor(),
                        new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                            @Override
                            public void onResult(GetCredentialResponse result) {
                                Credential credential = result.getCredential();
                                if (credential instanceof CustomCredential
                                        && GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(credential.getType())) {
                                    try {
                                        GoogleIdTokenCredential google = GoogleIdTokenCredential.createFrom(credential.getData());
                                        String name = google.getDisplayName() == null ? "" : google.getDisplayName();
                                        emitSignal("sign_in_success", google.getIdToken(), google.getId(), name);
                                    } catch (Exception e) {
                                        emitSignal("sign_in_failed", "Bad Google credential: " + e.getMessage());
                                    }
                                } else {
                                    emitSignal("sign_in_failed", "Unexpected credential type");
                                }
                            }

                            @Override
                            public void onError(@NonNull GetCredentialException e) {
                                if (e instanceof GetCredentialProviderConfigurationException
                                        || e instanceof GetCredentialUnsupportedException) {
                                    // Old Google Play services: fall back to the classic Google Sign-In screen.
                                    legacySignIn(activity, webClientId);
                                } else if (e instanceof GetCredentialCancellationException) {
                                    emitSignal("sign_in_failed", "cancelled");
                                } else {
                                    emitSignal("sign_in_failed", e.getClass().getSimpleName() + ": " + e.getMessage());
                                }
                            }
                        });
            } catch (Exception e) {
                emitSignal("sign_in_failed", e.getClass().getSimpleName() + ": " + e.getMessage());
            }
        });
    }

    /** Clears the remembered Google account choice so the picker shows next time. */
    @UsedByGodot
    public void signOut() {
        final Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        activity.runOnUiThread(() -> CredentialManager.create(activity).clearCredentialStateAsync(
                new ClearCredentialStateRequest(), new CancellationSignal(),
                mainExecutor(),
                new CredentialManagerCallback<Void, ClearCredentialException>() {
                    @Override
                    public void onResult(Void unused) {
                    }

                    @Override
                    public void onError(@NonNull ClearCredentialException e) {
                    }
                }));
    }

    // ---------------------------------------------------------------- legacy fallback

    private static final int RC_LEGACY_SIGN_IN = 9431;

    private GoogleSignInClient legacyClient(Activity activity, String webClientId) {
        GoogleSignInOptions gso = new GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
                .requestIdToken(webClientId)
                .requestEmail()
                .build();
        return GoogleSignIn.getClient(activity, gso);
    }

    private void legacySignIn(Activity activity, String webClientId) {
        try {
            GoogleSignInClient client = legacyClient(activity, webClientId);
            client.signOut().addOnCompleteListener(t ->
                    activity.startActivityForResult(client.getSignInIntent(), RC_LEGACY_SIGN_IN));
        } catch (Exception e) {
            emitSignal("sign_in_failed", "Legacy sign-in: " + e.getMessage());
        }
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != RC_LEGACY_SIGN_IN) {
            return;
        }
        try {
            GoogleSignInAccount account = GoogleSignIn.getSignedInAccountFromIntent(data).getResult(ApiException.class);
            String name = account.getDisplayName() == null ? "" : account.getDisplayName();
            String email = account.getEmail() == null ? "" : account.getEmail();
            if (account.getIdToken() == null) {
                emitSignal("sign_in_failed", "Google did not return an ID token");
            } else {
                emitSignal("sign_in_success", account.getIdToken(), email, name);
            }
        } catch (ApiException e) {
            // 12501 = user cancelled; 7 = network error; 10 = developer error (SHA-1 / client id)
            if (e.getStatusCode() == 12501) {
                emitSignal("sign_in_failed", "cancelled");
            } else {
                emitSignal("sign_in_failed", "Google sign-in error " + e.getStatusCode());
            }
        }
    }
}