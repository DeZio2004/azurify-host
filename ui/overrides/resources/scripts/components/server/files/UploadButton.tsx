import axios, { AxiosProgressEvent } from 'axios';
import getFileUploadUrl from '@/api/server/files/getFileUploadUrl';
import tw from 'twin.macro';
import { Button } from '@/components/elements/button/index';
import React, { useEffect, useRef, useState } from 'react';
import { Dialog } from '@/components/elements/dialog';
import { ModalMask } from '@/components/elements/Modal';
import Fade from '@/components/elements/Fade';
import useEventListener from '@/plugins/useEventListener';
import { useFlashKey } from '@/plugins/useFlash';
import useFileManagerSwr from '@/plugins/useFileManagerSwr';
import { ServerContext } from '@/state/server';
import { WithClassname } from '@/components/types';
import Portal from '@/components/elements/Portal';
import { CloudUploadIcon } from '@heroicons/react/outline';
import { useSignal } from '@preact/signals-react';

function isFileOrDirectory(event: DragEvent): boolean {
    if (!event.dataTransfer?.types) {
        return false;
    }

    return event.dataTransfer.types.some((value) => value.toLowerCase() === 'files');
}

export default ({ className }: WithClassname) => {
    const fileUploadInput = useRef<HTMLInputElement>(null);

    const visible = useSignal(false);
    const timeouts = useSignal<NodeJS.Timeout[]>([]);
    // AZURIFY: the Upload button opens a dialog with a drop zone and a "Choose files" button.
    const [dialogOpen, setDialogOpen] = useState(false);
    const [dragOver, setDragOver] = useState(false);

    const { mutate } = useFileManagerSwr();
    const { addError, clearAndAddHttpError } = useFlashKey('files');

    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const directory = ServerContext.useStoreState((state) => state.files.directory);
    const { clearFileUploads, removeFileUpload, pushFileUpload, setUploadProgress } = ServerContext.useStoreActions(
        (actions) => actions.files
    );

    useEventListener(
        'dragenter',
        (e) => {
            // While the upload dialog is open its own drop zone handles the drag.
            if (dialogOpen) return;
            e.preventDefault();
            e.stopPropagation();
            if (isFileOrDirectory(e)) {
                visible.value = true;
            }
        },
        { capture: true }
    );

    useEventListener('dragexit', () => (visible.value = false), { capture: true });

    useEventListener('keydown', () => (visible.value = false));

    useEffect(() => {
        return () => timeouts.value.forEach(clearTimeout);
    }, []);

    const onUploadProgress = (data: AxiosProgressEvent, name: string) => {
        setUploadProgress({ name, loaded: data.loaded });
    };

    const onFileSubmission = (files: FileList) => {
        setDialogOpen(false);
        setDragOver(false);
        clearAndAddHttpError();
        const list = Array.from(files);
        if (list.some((file) => !file.type && (!file.size || file.size === 4096))) {
            return addError('Folder uploads are not supported.', 'Error');
        }

        const uploads = list.map((file) => {
            const controller = new AbortController();
            pushFileUpload({
                name: file.name,
                data: { abort: controller, loaded: 0, total: file.size },
            });

            return () =>
                getFileUploadUrl(uuid).then((url) =>
                    axios
                        .post(
                            url,
                            { files: file },
                            {
                                signal: controller.signal,
                                headers: { 'Content-Type': 'multipart/form-data' },
                                params: { directory },
                                onUploadProgress: (data) => onUploadProgress(data, file.name),
                            }
                        )
                        .then(() => timeouts.value.push(setTimeout(() => removeFileUpload(file.name), 500)))
                );
        });

        Promise.all(uploads.map((fn) => fn()))
            .then(() => mutate())
            .catch((error) => {
                clearFileUploads();
                clearAndAddHttpError(error);
            });
    };

    return (
        <>
            <Portal>
                <Fade appear in={visible.value} timeout={75} key={'upload_modal_mask'} unmountOnExit>
                    <ModalMask
                        onClick={() => (visible.value = false)}
                        onDragOver={(e) => e.preventDefault()}
                        onDrop={(e) => {
                            e.preventDefault();
                            e.stopPropagation();

                            visible.value = false;
                            if (!e.dataTransfer?.files.length) return;

                            onFileSubmission(e.dataTransfer.files);
                        }}
                    >
                        <div className={'w-full flex items-center justify-center pointer-events-none'}>
                            <div
                                className={
                                    'flex items-center space-x-4 bg-black w-full ring-4 ring-blue-200 ring-opacity-60 rounded p-6 mx-10 max-w-sm'
                                }
                            >
                                <CloudUploadIcon className={'w-10 h-10 flex-shrink-0'} />
                                <p className={'font-header flex-1 text-lg text-neutral-100 text-center'}>
                                    Drag and drop files to upload.
                                </p>
                            </div>
                        </div>
                    </ModalMask>
                </Fade>
            </Portal>
            <input
                type={'file'}
                ref={fileUploadInput}
                css={tw`hidden`}
                onChange={(e) => {
                    if (!e.currentTarget.files) return;

                    onFileSubmission(e.currentTarget.files);
                    if (fileUploadInput.current) {
                        fileUploadInput.current.files = null;
                    }
                }}
                multiple
            />
            <Dialog
                open={dialogOpen}
                onClose={() => {
                    setDialogOpen(false);
                    setDragOver(false);
                }}
                title={'Upload files'}
                description={`Files go into ${directory === '/' ? 'the main folder' : directory}.`}
            >
                <div
                    className={'mt-4 flex flex-col items-center justify-center text-center px-6 py-10 transition-colors'}
                    style={{
                        borderRadius: 16,
                        border: `2px dashed ${dragOver ? '#22d3ee' : 'rgba(148, 197, 255, 0.28)'}`,
                        background: dragOver ? 'rgba(34, 211, 238, 0.08)' : 'rgba(255, 255, 255, 0.03)',
                    }}
                    onDragEnter={(e) => {
                        e.preventDefault();
                        setDragOver(true);
                    }}
                    onDragOver={(e) => {
                        e.preventDefault();
                        if (!dragOver) setDragOver(true);
                    }}
                    onDragLeave={(e) => {
                        if (!e.currentTarget.contains(e.relatedTarget as Node)) setDragOver(false);
                    }}
                    onDrop={(e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        setDragOver(false);
                        if (e.dataTransfer?.files.length) onFileSubmission(e.dataTransfer.files);
                    }}
                >
                    <CloudUploadIcon className={'w-12 h-12'} style={{ color: dragOver ? '#22d3ee' : '#8195b3' }} />
                    <p className={'font-header text-lg text-neutral-100 mt-3'}>
                        {dragOver ? 'Drop to upload' : 'Drag and drop files here'}
                    </p>
                    <p className={'text-sm text-neutral-400 mt-1'}>or</p>
                    <Button className={'mt-3'} onClick={() => fileUploadInput.current && fileUploadInput.current.click()}>
                        Choose files
                    </Button>
                    <p className={'text-xs text-neutral-500 mt-4'}>You can pick several files at once. Folders are not supported.</p>
                </div>
            </Dialog>
            <Button className={className} onClick={() => setDialogOpen(true)}>
                Upload
            </Button>
        </>
    );
};
