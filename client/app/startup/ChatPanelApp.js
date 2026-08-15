/**
 * ChatPanelApp — React entry point for the AI Persona Chat Panel.
 *
 * Mounted from HAML via:
 *   react_component("ChatPanelApp", props: { listing_id, persona_name })
 *
 * Props are passed from the server-rendered HAML template and injected
 * into the React component tree by react-on-rails.
 */
import React, { useState, useCallback } from 'react';
import ChatPanel from '../components/ChatPanel/ChatPanel';

/**
 * A wrapper that manages the open/closed state of the chat panel.
 * Renders a floating chat button when closed, and the full panel when open.
 *
 * @param {Object} props
 * @param {number} props.listing_id - The listing ID (persona)
 * @param {string} [props.persona_name] - Display name of the persona
 */
const ChatPanelApp = ({ listing_id, persona_name }) => {
  const [isOpen, setIsOpen] = useState(false);

  const handleOpen = useCallback(() => setIsOpen(true), []);
  const handleClose = useCallback(() => setIsOpen(false), []);

  return (
    <>
      {/* Floating chat trigger button */}
      {!isOpen && (
        <button
          onClick={handleOpen}
          className="chatPanel__trigger"
          aria-label="Open AI chat"
          type="button"
          style={{
            position: 'fixed',
            bottom: '24px',
            right: '24px',
            width: '56px',
            height: '56px',
            borderRadius: '50%',
            background: '#59b3a2',
            color: '#fff',
            border: 'none',
            cursor: 'pointer',
            boxShadow: '0 4px 12px rgba(0, 0, 0, 0.2)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 999,
            transition: 'background-color 0.15s ease',
          }}
        >
          {/* Chat bubble icon */}
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path
              d="M20 2H4C2.9 2 2 2.9 2 4V22L6 18H20C21.1 18 22 17.1 22 16V4C22 2.9 21.1 2 20 2ZM20 16H5.17L4 17.17V4H20V16Z"
              fill="currentColor"
            />
            <path
              d="M7 9H17V11H7V9ZM13 14H7V12H13V14ZM17 8H7V6H17V8Z"
              fill="currentColor"
            />
          </svg>
        </button>
      )}

      {/* Chat panel overlay */}
      {isOpen && (
        <ChatPanel
          listingId={listing_id}
          personaName={persona_name}
          onClose={handleClose}
        />
      )}
    </>
  );
};

export default ChatPanelApp;
