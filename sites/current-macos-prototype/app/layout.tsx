import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Current macOS Prototype",
  description: "Interactive prototype for the Current macOS Git client.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
